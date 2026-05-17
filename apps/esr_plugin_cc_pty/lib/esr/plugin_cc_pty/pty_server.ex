defmodule Esr.PluginCcPty.PtyServer do
  @moduledoc """
  PTY-managed child process running `claude` directly.

  Phase 4-completion PR 8: ESR's first plugin-managed child process.
  Uses `:exec.run/2` (erlexec) for PTY allocation (claude TUI needs
  a real tty). Post-Phase-5 (Allen 2026-05-17): inlined the previous
  `bash cc-bridge-attach.sh` wrapper into `spawn_claude_directly/1`,
  and routes `agent_uri` through mcp.json (not env-var passthrough)
  so the Python bridge always announces with the correct agent_uri.

  ## Auto-confirm dev-channels dialog (ported from old esr)

  `claude --dangerously-load-development-channels server:esr-bridge`
  prompts the operator with an interactive dialog ("Loading development
  channels..." / "I am using this for local development"). When ESR
  spawns claude headlessly there's no human at the terminal — we must
  auto-confirm.

  Pattern (per Allen's directive, matching old esr's
  `feishu_chat_proxy.maybe_confirm_dev_channels/1`):
  1. Accumulate stdout in `:pty_buffer`
  2. ANSI-strip via `Esr.AnsiStrip.strip/1` (codes interleave between
     words; substring-match on raw bytes won't work)
  3. Detect BOTH `"Loading development channels"` AND `"I am using
     this for local development"` in stripped text
  4. On first match: `:exec.send(os_pid, "1\\r")` and flip
     `:dev_channels_confirmed` to true so we don't re-fire

  Other paths (CLI flag / ENV var / --print mode) were validated as
  unreliable in old esr — option B (prompt detection) is the only
  one that works (per Allen 2026-05-16).

  ## Crash policy

  Trap_exit + erlexec `:monitor` — child process death triggers stop;
  DynamicSupervisor restarts with backoff (3-in-60s default).

  ## Test mode

  In `Mix.env() == :test`, `:exec.run/2` is short-circuited. Real
  spawn requires host bash + script + claude binary; tests assert the
  Template Class path works without exercising claude itself.
  """

  use GenServer
  require Logger

  alias Esr.AnsiStrip

  defstruct [
    :agent_uri,
    :cwd,
    :exec_pid,
    :os_pid,
    :test_mode,
    # Optional cmd override — tests pass a mock script here instead of
    # needing a real claude binary. Production defaults to the inline
    # `claude --permission-mode bypassPermissions ...` invocation.
    :cmd_override,
    pty_buffer: "",
    dev_channels_confirmed: false
  ]

  def start_link(args) when is_map(args) do
    GenServer.start_link(__MODULE__, args)
  end

  @doc """
  Status snapshot for `/admin/agents/:uri` LV (Phase 5 PR 3).

  Returns the live PTY's introspectable state — operator-facing fields
  only. Heavy fields (full pty_buffer) are trimmed; recent output is
  ANSI-stripped + bounded.
  """
  def status(pid) when is_pid(pid) do
    state = :sys.get_state(pid, 500)

    recent_lines =
      state.pty_buffer
      |> AnsiStrip.strip()
      |> String.split("\n")
      |> Enum.reject(&(&1 == ""))
      |> Enum.take(-50)

    %{
      agent_uri: state.agent_uri,
      cwd: state.cwd,
      os_pid: state.os_pid,
      exec_pid: state.exec_pid,
      test_mode: state.test_mode,
      running: state.exec_pid != nil or state.test_mode,
      dev_channels_confirmed: state.dev_channels_confirmed,
      recent_output: recent_lines,
      buffer_bytes: byte_size(state.pty_buffer)
    }
  end

  @doc """
  Walks the DynamicSupervisor's children looking for a PtyServer whose
  state's `agent_uri` matches. Returns `{:ok, pid}` or `:error`.

  Cheap enough for v1 (~few children typically); switch to a Registry
  if PtyServer count gets into the dozens.
  """
  def find_by_agent_uri(%URI{} = agent_uri) do
    target = URI.to_string(agent_uri)

    sup_pid = Process.whereis(EsrPluginCcPty.PtyServerSupervisor)

    if sup_pid do
      DynamicSupervisor.which_children(sup_pid)
      |> Enum.find_value(:error, fn
        {_, child_pid, :worker, _} when is_pid(child_pid) ->
          try do
            state = :sys.get_state(child_pid, 500)
            if URI.to_string(state.agent_uri) == target, do: {:ok, child_pid}, else: nil
          catch
            _, _ -> nil
          end

        _ ->
          nil
      end)
    else
      :error
    end
  end

  @doc """
  Write bytes to the PTY's stdin (called by Esr.Behavior.Pty.invoke(:write, ...)).

  Returns `:ok` on success or `{:error, reason}`. Test_mode short-circuits
  to `:ok` without invoking erlexec.
  """
  def write_input(pid, bytes) when is_pid(pid) and is_binary(bytes) do
    GenServer.call(pid, {:write_input, bytes}, 1000)
  end

  @doc "PubSub topic for an agent's PTY stdout/stderr stream (Phase 5 PR 4)."
  def output_topic(%URI{} = agent_uri),
    do: "pty:output:" <> URI.to_string(agent_uri)

  @doc "List all live PtyServer agent_uris under the DynamicSupervisor."
  def list_agents do
    sup_pid = Process.whereis(EsrPluginCcPty.PtyServerSupervisor)

    if sup_pid do
      DynamicSupervisor.which_children(sup_pid)
      |> Enum.flat_map(fn
        {_, child_pid, :worker, _} when is_pid(child_pid) ->
          try do
            state = :sys.get_state(child_pid, 500)
            [%{agent_uri: state.agent_uri, pid: child_pid, os_pid: state.os_pid}]
          catch
            _, _ -> []
          end

        _ ->
          []
      end)
    else
      []
    end
  end

  @impl true
  def init(args) do
    agent_uri = Map.fetch!(args, :agent_uri)
    cwd = Map.get(args, :cwd, File.cwd!())
    test_mode = Map.get(args, :test_mode, Mix.env() == :test)
    cmd_override = Map.get(args, :cmd_override)

    Process.flag(:trap_exit, true)

    state = %__MODULE__{
      agent_uri: agent_uri,
      cwd: cwd,
      test_mode: test_mode,
      cmd_override: cmd_override
    }

    {:ok, state, {:continue, :spawn_pty}}
  end

  @impl true
  def handle_continue(:spawn_pty, %__MODULE__{test_mode: true} = state) do
    Logger.info(
      "PtyServer test_mode: would spawn claude for " <>
        "agent=#{URI.to_string(state.agent_uri)} cwd=#{state.cwd}"
    )

    {:noreply, state}
  end

  def handle_continue(:spawn_pty, state) do
    case spawn_claude_directly(state) do
      {:ok, exec_pid, os_pid} ->
        Logger.info(
          "PtyServer spawned claude os_pid=#{os_pid} for agent=#{URI.to_string(state.agent_uri)}"
        )

        # Per old esr's PR-24 lesson: claude's TUI queries TIOCGWINSZ
        # to learn terminal size and BLOCKS rendering past initial
        # control sequences until it gets a non-zero size. Send a
        # default 120×40 winsize ~500ms after spawn (gives claude
        # time to finish initial DA query).
        # Per memory `feedback_verify_ffi_arg_order`: rows FIRST,
        # cols second.
        Process.send_after(self(), :send_default_winsize, 500)

        {:noreply, %{state | exec_pid: exec_pid, os_pid: os_pid}}

      {:error, reason} ->
        Logger.error("PtyServer: spawn failed: #{inspect(reason)}")
        {:stop, {:spawn_failed, reason}, state}
    end
  end

  # Generates mcp.json via the in-process McpConfigWriter (with the
  # agent_uri baked in so the Python bridge announces deterministically),
  # then runs `claude --permission-mode bypassPermissions
  # --dangerously-load-development-channels server:esr-bridge
  # --mcp-config <path>` under erlexec's PTY.
  defp spawn_claude_directly(state) do
    cmd_str =
      case state.cmd_override do
        nil ->
          {:ok, mcp_path} =
            Esr.Bridge.V1Prototype.McpConfigWriter.write!(
              agent_uri: URI.to_string(state.agent_uri)
            )

          "claude --permission-mode bypassPermissions " <>
            "--dangerously-load-development-channels server:esr-bridge " <>
            "--mcp-config #{mcp_path}"

        cmd when is_binary(cmd) ->
          cmd
      end

    env = build_env(state)

    case :exec.run(String.to_charlist(cmd_str), [
           :pty,
           :monitor,
           # `:stdin` keeps the child's stdin pipe open so :exec.send/2
           # can write to it (dev-channels auto-confirm "1\r"). Without
           # this, child sees EOF on stdin → `read` fails → claude can't
           # see operator input.
           :stdin,
           {:env, env},
           {:cd, String.to_charlist(state.cwd)},
           :stderr,
           :stdout
         ]) do
      {:ok, exec_pid, os_pid} -> {:ok, exec_pid, os_pid}
      err -> err
    end
  end

  defp build_env(state) do
    # Pass operator's existing env through (proxy / API key / etc) so
    # operator-set vars from their shell where `mix phx.server` runs
    # reach claude. The two we own are ESR_AGENT_URI (informational)
    # and ESRD_URL (so the spawned MCP bridge knows where to announce).
    base = :os.getenv() |> Enum.map(fn s ->
      case :string.split(s, ~c"=") do
        [k, v] -> {k, v}
        _ -> {s, ~c""}
      end
    end)

    overrides = [
      {~c"ESR_AGENT_URI", String.to_charlist(URI.to_string(state.agent_uri))}
    ]

    overrides ++ base
  end

  # --- erlexec messages -----------------------------------------------

  @impl true
  def handle_call({:write_input, _bytes}, _from, %__MODULE__{test_mode: true} = state) do
    # Tests record bytes_written in slice without invoking erlexec; the
    # invariant test asserts dispatch path was followed, not that the
    # bytes physically reached a real PTY.
    {:reply, :ok, state}
  end

  def handle_call({:write_input, bytes}, _from, %__MODULE__{exec_pid: exec_pid} = state)
      when exec_pid != nil do
    try do
      :exec.send(exec_pid, bytes)
      {:reply, :ok, state}
    catch
      kind, reason ->
        Logger.warning(
          "PtyServer.write_input failed (#{inspect(kind)}, #{inspect(reason)})"
        )

        {:reply, {:error, {kind, reason}}, state}
    end
  end

  def handle_call({:write_input, _bytes}, _from, state),
    do: {:reply, {:error, :pty_not_alive}, state}

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    Logger.warning(
      "PtyServer: child process exited for #{URI.to_string(state.agent_uri)}: #{inspect(reason)}"
    )

    {:stop, {:child_exited, reason}, state}
  end

  # stdout / stderr chunks from erlexec
  def handle_info({stream, _os_pid, data}, state) when stream in [:stdout, :stderr] do
    chunk = if is_binary(data), do: data, else: IO.iodata_to_binary(data)

    Logger.debug(
      "PtyServer[#{state.os_pid}] #{stream}: #{chunk |> AnsiStrip.strip() |> String.trim_trailing()}"
    )

    # Phase 5 PR 4: fan out raw chunk to LV Pty-Web subscribers
    # (xterm renders escape sequences directly — no ANSI strip here).
    Phoenix.PubSub.broadcast(
      EsrCore.PubSub,
      output_topic(state.agent_uri),
      {:pty_output, state.agent_uri, chunk}
    )

    new_buffer = state.pty_buffer <> chunk
    state = %{state | pty_buffer: new_buffer}

    state = maybe_confirm_dev_channels(state)

    {:noreply, state}
  end

  def handle_info(:send_default_winsize, %__MODULE__{os_pid: nil} = state),
    do: {:noreply, state}

  def handle_info(:send_default_winsize, %__MODULE__{os_pid: os_pid} = state) do
    # Per `feedback_verify_ffi_arg_order`: rows first, cols second.
    try do
      :exec.winsz(os_pid, 40, 120)
    catch
      kind, why ->
        Logger.warning(
          "PtyServer: winsz send failed (#{inspect(kind)}, #{inspect(why)})"
        )
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # --- dev-channels auto-confirm (ported from old esr) -----------------

  # Once-only auto-confirm of claude's `--dangerously-load-development-
  # channels` dialog. We match against the buffer's stripped content
  # (ANSI codes mangle "Loading development channels" into segments
  # like "Loading[1Cdevelopment[1Cchannels" — strip first, match
  # after).
  #
  # The first match writes "1\r" to the PTY's stdin via erlexec —
  # "1" selects the "I am using this for local development" option,
  # "\r" submits.
  defp maybe_confirm_dev_channels(%__MODULE__{dev_channels_confirmed: true} = state),
    do: state

  defp maybe_confirm_dev_channels(%__MODULE__{exec_pid: nil} = state), do: state

  defp maybe_confirm_dev_channels(%__MODULE__{pty_buffer: buf, exec_pid: exec_pid} = state) do
    stripped = AnsiStrip.strip(buf)

    if String.contains?(stripped, "Loading development channels") and
         String.contains?(stripped, "I am using this for local development") do
      Logger.info(
        "PtyServer: auto-confirming dev-channels dialog for #{URI.to_string(state.agent_uri)}"
      )

      try do
        :exec.send(exec_pid, "1\r")
      catch
        kind, why ->
          Logger.warning(
            "PtyServer: dev-channels confirm send failed (#{inspect(kind)}, #{inspect(why)})"
          )
      end

      # Clear buffer after confirm so it doesn't grow unbounded — also
      # prevents accidental re-detection (belt-and-suspenders with
      # :dev_channels_confirmed flag).
      %{state | dev_channels_confirmed: true, pty_buffer: ""}
    else
      # Trim buffer if it grows past 64KB — we only need the most recent
      # output for prompt detection.
      buf2 =
        if byte_size(buf) > 64 * 1024 do
          binary_part(buf, byte_size(buf) - 16 * 1024, 16 * 1024)
        else
          buf
        end

      %{state | pty_buffer: buf2}
    end
  end

  @impl true
  def terminate(_reason, %__MODULE__{exec_pid: nil}), do: :ok

  def terminate(_reason, %__MODULE__{exec_pid: pid}) do
    try do
      :exec.stop(pid)
    catch
      _, _ -> :ok
    end

    :ok
  end
end
