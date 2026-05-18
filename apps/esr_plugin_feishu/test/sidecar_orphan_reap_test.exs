defmodule EsrPluginFeishu.SidecarOrphanReapTest do
  @moduledoc """
  Phase 7 PR 35 invariant — the Node sidecar exits when its parent
  Erlang Port closes, preventing orphan accumulation.

  ## Background

  `Esr.PluginFeishu.WsClient` spawns the Node sidecar via
  `Port.open({:spawn_executable, node_bin}, ...)`. Erlang
  `:spawn_executable` Ports do NOT propagate signals to the child
  process when the BEAM VM exits — the OS reparents the Node
  process to PID 1 and it keeps running.

  Symptom (observed in Phase 6 PR 27 debugging): every phx.server
  restart leaks one orphan sidecar. Three orphans accumulated over
  one day, all racing for Feishu inbound events, silently stealing
  messages.

  ## Fix (PR 35)

  Sidecar reads its own stdin via `process.stdin.on('end', () =>
  process.exit())`. When the Elixir Port closes (parent dies /
  Port.close called / VM exits), stdin sees EOF. The handler fires
  and the sidecar exits cleanly. Universal pattern for any
  Port-spawned subprocess sidecar.

  ## Test strategy

  Two tests:

  1. **Static check** — grep the source file for the handler. Catches
     the most likely regression (someone refactors main.js and drops
     the handler).
  2. **Integration check** — spawn a real Port, close it, assert the
     OS pid is dead within 3 seconds. Tagged `:slow` so it only runs
     when explicitly included.

  The integration check is the strongest guarantee but takes ~3s
  per run; the static check is fast and catches the common refactor
  regression. CI runs both via `mix test --include slow`.
  """

  use ExUnit.Case, async: true

  @sidecar_path Path.expand(
                  "../priv/ws_sidecar/main.js",
                  __DIR__
                )

  test "sidecar main.js registers a stdin EOF handler that calls process.exit" do
    assert File.exists?(@sidecar_path),
           "sidecar main.js not found at #{@sidecar_path}; cannot test orphan reap"

    source = File.read!(@sidecar_path)

    # The exact handler we expect (or a near-equivalent). We're lenient
    # on whitespace + style but strict that BOTH the EOF event handler
    # AND the exit call are present.
    assert source =~ ~r/process\.stdin\.on\(\s*['"]end['"]/,
           "main.js does not register a stdin 'end' (EOF) handler — orphan reap is broken. " <>
             "Phase 6 PR 27 lesson: orphan sidecars steal Feishu inbound events. " <>
             "Add: process.stdin.on('end', () => process.exit(0)); + process.stdin.resume();"

    assert source =~ ~r/process\.stdin\.resume\(\)/,
           "main.js registers an 'end' handler but doesn't call process.stdin.resume() — " <>
             "without resume() the stream stays paused and 'end' never fires"

    # The handler body should call process.exit (otherwise the sidecar
    # just logs and keeps running). Take a window starting at the
    # handler registration and look for process.exit within the next
    # ~400 chars (the handler body, including try/catch wrappers, is
    # always well under this).
    {pos, _len} = Regex.run(~r/process\.stdin\.on\(\s*['"]end['"]/, source, return: :index) |> hd()

    window = String.slice(source, pos, 400)

    assert window =~ ~r/process\.exit/,
           "EOF handler does not call process.exit within its body — " <>
             "the sidecar will log on EOF but won't exit, leaving an orphan. " <>
             "Window inspected: #{inspect(window)}"
  end

  @tag :slow
  @tag timeout: 30_000
  test "spawned sidecar exits within 3s after Port closes (integration)" do
    node_bin = System.find_executable("node")

    if is_nil(node_bin) do
      flunk("node binary not found in PATH — cannot run integration test")
    end

    # Spawn the sidecar with deliberately bogus credentials.
    # It will fail to connect, but the EOF handler is registered
    # before the SDK initialization, so the reap behavior is testable.
    port =
      Port.open(
        {:spawn_executable, node_bin},
        [
          :binary,
          :exit_status,
          {:args, [@sidecar_path]},
          {:env,
           [
             {~c"FEISHU_APP_ID", ~c"test_app_id_orphan_reap"},
             {~c"FEISHU_APP_SECRET", ~c"test_app_secret_orphan_reap"}
           ]},
          {:line, 65_536}
        ]
      )

    # Get the OS pid of the Node process so we can verify it actually died.
    {:os_pid, os_pid} = Port.info(port, :os_pid)

    # Confirm the process is alive before we close.
    assert os_pid_alive?(os_pid),
           "sidecar with pid #{os_pid} died before we could test EOF reap — " <>
             "check main.js for a fatal() that fires before stdin handler registration"

    # Close the Port → Elixir closes stdin → Node sees EOF → handler fires → exit.
    Port.close(port)

    # Poll for up to 3s, asserting the pid is gone.
    assert eventually_dead?(os_pid, 3_000),
           "sidecar pid #{os_pid} still alive 3s after Port close — " <>
             "orphan reap mechanism is broken (Phase 6 PR 27 regression)"
  end

  defp os_pid_alive?(os_pid) do
    case System.cmd("kill", ["-0", to_string(os_pid)], stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  end

  defp eventually_dead?(os_pid, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    eventually_dead?(os_pid, deadline, 100)
  end

  defp eventually_dead?(os_pid, deadline, poll_ms) do
    if os_pid_alive?(os_pid) do
      now = System.monotonic_time(:millisecond)

      if now < deadline do
        Process.sleep(poll_ms)
        eventually_dead?(os_pid, deadline, poll_ms)
      else
        false
      end
    else
      true
    end
  end
end
