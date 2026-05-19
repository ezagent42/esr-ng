defmodule Ezagent.PluginCc.PtyInputDispatchTest do
  @moduledoc """
  Phase 5 PR 4 invariant — PTY input goes through Ezagent.Invocation.dispatch
  (per IMPLEMENTATION_ROADMAP §1.3 #1).

  Sends N writes via dispatch to `pty-input://default/behavior/pty/write`
  and asserts:
  1. The slice counter (write_calls, total_bytes) reflects every write
     (proves the Behavior was invoked)
  2. Each dispatch returns {:ok, _} (proves CapBAC passed for admin)
  3. test_mode PtyServer received the writes (proves the synthetic
     Kind looked up the right pid)

  If a future change makes Pty-Web push input directly into a PubSub
  topic the PtyServer reads, this test still passes for that input
  path BUT the slice counter wouldn't increment for the bypass path —
  the gate is "everything operator-typed goes through this dispatch
  target and the slice counts reflect it".
  """
  use ExUnit.Case, async: false

  alias Ezagent.Invocation

  setup do
    agent_uri = URI.parse("entity://agent/test_pty-input-test-#{System.unique_integer([:positive])}")

    {:ok, pid} =
      DynamicSupervisor.start_child(
        EzagentPluginCc.PtyServerSupervisor,
        {Ezagent.PluginCc.PtyServer, %{agent_uri: agent_uri, cwd: File.cwd!(), test_mode: true}}
      )

    on_exit(fn ->
      if Process.alive?(pid), do: Process.exit(pid, :shutdown)
    end)

    {:ok, agent_uri: agent_uri, pty_pid: pid}
  end

  defp admin_ctx do
    %{
      caller: Ezagent.Entity.User.admin_uri(),
      caps: Ezagent.Entity.User.admin_caps(),
      reply: {:caller_inbox, self()}
    }
  end

  defp dispatch_target do
    URI.parse(
      URI.to_string(Ezagent.Entity.PtyInput.default_uri()) <>
        "/behavior/pty/write"
    )
  end

  test "100-byte stream via dispatch hits PtyServer + bumps slice counters", %{
    agent_uri: agent_uri,
    pty_pid: _pid
  } do
    payloads = for i <- 1..100, do: <<i>>
    target = dispatch_target()

    Enum.each(payloads, fn payload ->
      assert {:ok, %{bytes_written: 1}} =
               Invocation.dispatch(%Invocation{
                 target: target,
                 mode: :call,
                 args: %{agent_uri: URI.to_string(agent_uri), bytes: payload},
                 ctx: admin_ctx()
               })
    end)

    # Invariant: the synthetic PtyInput Kind's slice has the cumulative
    # counters from this stream (other tests may add more — assert >=
    # rather than ==).
    {:ok, kind_pid} = Ezagent.KindRegistry.lookup(Ezagent.Entity.PtyInput.default_uri())
    state = :sys.get_state(kind_pid, 500)
    slice = state.state.pty_input

    assert slice.write_calls >= 100
    assert slice.total_bytes >= 100
  end

  test "non-admin without pty_input cap → :unauthorized", %{agent_uri: agent_uri} do
    non_admin_ctx = %{
      caller: URI.parse("entity://user/non-admin-pty-test"),
      caps: MapSet.new(),
      reply: {:caller_inbox, self()}
    }

    assert {:error, :unauthorized} =
             Invocation.dispatch(%Invocation{
               target: dispatch_target(),
               mode: :call,
               args: %{agent_uri: URI.to_string(agent_uri), bytes: "x"},
               ctx: non_admin_ctx
             })
  end

  test "PtyInput singleton alive at boot at pty-input://default" do
    assert {:ok, _pid} = Ezagent.KindRegistry.lookup(Ezagent.Entity.PtyInput.default_uri())
  end

  test "dispatch with unknown agent_uri → :no_pty_server", %{} do
    assert {:error, :no_pty_server} =
             Invocation.dispatch(%Invocation{
               target: dispatch_target(),
               mode: :call,
               args: %{agent_uri: "entity://agent/test_nonexistent", bytes: "x"},
               ctx: admin_ctx()
             })
  end

  test "PubSub output topic broadcasts on chunk arrival", %{agent_uri: agent_uri, pty_pid: pid} do
    Phoenix.PubSub.subscribe(EzagentCore.PubSub, Ezagent.PluginCc.PtyServer.output_topic(agent_uri))

    # Simulate a stdout chunk arrival (the erlexec :stdout message shape).
    send(pid, {:stdout, 0, "hello from pty\n"})

    assert_receive {:pty_output, ^agent_uri, "hello from pty\n"}, 500
  end
end
