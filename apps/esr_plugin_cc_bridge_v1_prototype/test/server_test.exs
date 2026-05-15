defmodule Esr.Bridge.V1Prototype.ServerTest do
  use ExUnit.Case
  alias Esr.Bridge.V1Prototype.Server

  setup do
    # Subscribe to the bridge events topic so we observe the initial
    # `hello` and any RPC replies broadcast for view consumers.
    Phoenix.PubSub.subscribe(EsrCore.PubSub, Server.topic())
    :ok
  end

  test "spawns bridge, receives hello, then RPC round-trip works" do
    {:ok, _pid} = Server.start_link([])

    # Initial hello from the Python bridge.
    assert_receive {:bridge_event, %{"method" => "hello"}}, 2_000

    # status/0 should reflect :ready once hello arrived.
    assert Server.status() in [:starting, :ready]
    # Wait a tick for the GenServer to handle the hello message.
    Process.sleep(20)
    assert Server.status() == :ready

    # ping/pong via the stdio RPC.
    assert {:ok, "pong"} = Server.call("ping", %{})

    # echo round-trip.
    assert {:ok, %{"echo" => "round-trip"}} = Server.call("echo", %{"msg" => "round-trip"})

    # We should have seen broadcasts mirror each reply (for LV consumers).
    assert_receive {:bridge_reply, _id, "pong"}
    assert_receive {:bridge_reply, _id, %{"echo" => "round-trip"}}
  end

  test "bridge exit emits telemetry + broadcasts :bridge_exited" do
    test_pid = self()
    ref = make_ref()

    :telemetry.attach(
      "bridge-v1-exit-test-#{System.unique_integer([:positive])}",
      [:esr, :bridge_v1, :exited],
      fn _e, _m, meta, _config -> send(test_pid, {ref, meta}) end,
      nil
    )

    {:ok, _pid} = Server.start_link([])
    assert_receive {:bridge_event, %{"method" => "hello"}}, 2_000

    # Trigger graceful shutdown via the RPC `shutdown` method.
    Server.call("shutdown", %{})

    # Should observe telemetry + PubSub broadcast.
    assert_receive {^ref, %{exit_status: 0}}, 2_000
    assert_receive {:bridge_exited, 0}, 2_000
  end

  test "status/0 returns :down when GenServer not started" do
    # GenServer not started in this test (the application is set to
    # auto_start: false in test env), so status should be :down before
    # we start_link.
    assert Server.status() == :down
  end
end
