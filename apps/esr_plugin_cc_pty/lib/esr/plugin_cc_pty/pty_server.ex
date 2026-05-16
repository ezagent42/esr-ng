defmodule Esr.PluginCcPty.PtyServer do
  @moduledoc """
  PTY-managed child process running `bash cc-bridge-attach.sh`.

  Phase 4-completion PR 8: ESR's first plugin-managed child process.
  Uses `:exec.run/2` (erlexec) for PTY allocation (claude TUI needs
  a real tty).

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
    pty_buffer: "",
    dev_channels_confirmed: false
  ]

  def start_link(args) when is_map(args) do
    GenServer.start_link(__MODULE__, args)
  end

  @impl true
  def init(args) do
    agent_uri = Map.fetch!(args, :agent_uri)
    cwd = Map.get(args, :cwd, File.cwd!())
    test_mode = Map.get(args, :test_mode, Mix.env() == :test)

    Process.flag(:trap_exit, true)

    state = %__MODULE__{
      agent_uri: agent_uri,
      cwd: cwd,
      test_mode: test_mode
    }

    {:ok, state, {:continue, :spawn_pty}}
  end

  @impl true
  def handle_continue(:spawn_pty, %__MODULE__{test_mode: true} = state) do
    Logger.info(
      "PtyServer test_mode: would spawn bash cc-bridge-attach.sh for " <>
        "agent=#{URI.to_string(state.agent_uri)} cwd=#{state.cwd}"
    )

    {:noreply, state}
  end

  def handle_continue(:spawn_pty, state) do
    script = Path.join([state.cwd, "scripts", "cc-bridge-attach.sh"])

    if File.exists?(script) do
      case spawn_via_exec(script, state) do
        {:ok, exec_pid, os_pid} ->
          Logger.info(
            "PtyServer spawned os_pid=#{os_pid} for agent=#{URI.to_string(state.agent_uri)}"
          )

          # Per old esr's PR-24 lesson: claude's TUI queries TIOCGWINSZ
          # to learn terminal size and BLOCKS rendering past initial
          # control sequences until it gets a non-zero size. erlexec
          # :pty doesn't set winsize by default — operator's
          # connecting terminal would normally provide it on connect,
          # but our headless spawn has no client. Send a default
          # 120×40 winsize ~500ms after spawn (gives claude time to
          # finish initial DA query).
          #
          # Per memory `feedback_verify_ffi_arg_order`: `:exec.winsz/3`
          # signature is `(os_pid, rows, cols)` — rows FIRST, cols
          # second. Old esr's PR-22 burned 3 PRs swapping these.
          Process.send_after(self(), :send_default_winsize, 500)

          {:noreply, %{state | exec_pid: exec_pid, os_pid: os_pid}}

        {:error, reason} ->
          Logger.error("PtyServer: spawn failed: #{inspect(reason)}")
          {:stop, {:spawn_failed, reason}, state}
      end
    else
      Logger.error("PtyServer: script not found at #{script}")
      {:stop, {:script_not_found, script}, state}
    end
  end

  defp spawn_via_exec(script, state) do
    env = build_env(state)

    case :exec.run(~c"bash " ++ String.to_charlist(script), [
           :pty,
           :monitor,
           # `:stdin` keeps the child's stdin pipe open so :exec.send/2
           # can write to it (e.g. dev-channels auto-confirm "1\r").
           # Without this, child sees EOF on stdin → `read` fails →
           # claude can't see operator input.
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
    [{~c"ESR_AGENT_URI", String.to_charlist(URI.to_string(state.agent_uri))}]
  end

  # --- erlexec messages -----------------------------------------------

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
