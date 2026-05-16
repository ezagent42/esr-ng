defmodule Esr.PluginCcPty.PtyServer do
  @moduledoc """
  PTY-managed child process running `bash cc-bridge-attach.sh`.

  Phase 4-completion PR 8: ESR's first plugin-managed child process.
  We use `:exec.run/2` (erlexec) for PTY allocation (claude TUI needs
  a real tty); the shell script itself runs `script -q /dev/null
  claude ...` internally so we get a 2-layer PTY (erlexec PTY → script
  PTY → claude). Acceptable for v1 — Phase 5 may collapse.

  ## State

      %{
        agent_uri: URI.t(),
        cwd: String.t(),
        exec_pid: integer() | nil,
        os_pid: integer() | nil
      }

  ## Crash policy

  GenServer crashes when erlexec reports `{:DOWN, ...}` for the OS
  process. The DynamicSupervisor (default `:one_for_one`) restarts
  with backoff. Phase 4 v1: 3-in-60s restart intensity (default).

  ## Test mode

  In `Mix.env() == :test`, `:exec.run/2` may not be available (depends
  on erlexec start) — `run_command/2` accepts a `:test_mode` flag that
  short-circuits to record the would-have-been command without
  spawning. Real spawn requires the host to have the shell script +
  bash available; the test invariant just asserts the GenServer +
  Template path works end-to-end.
  """

  use GenServer
  require Logger

  defstruct [:agent_uri, :cwd, :exec_pid, :os_pid, :test_mode]

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

    case :exec.run("bash #{script}", [
           :pty,
           :monitor,
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

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    Logger.warning(
      "PtyServer: child process exited for #{URI.to_string(state.agent_uri)}: #{inspect(reason)}"
    )

    {:stop, {:child_exited, reason}, state}
  end

  def handle_info({stream, _os_pid, data}, state) when stream in [:stdout, :stderr] do
    # Log child output (for now). Phase 5+ may forward to chat or a
    # dedicated console view.
    Logger.debug("PtyServer[#{state.os_pid}] #{stream}: #{String.trim_trailing(to_string(data))}")
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

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
