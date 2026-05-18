defmodule Ezagent.Bridge.V1Prototype.ServerTest do
  use ExUnit.Case
  alias Ezagent.Bridge.V1Prototype.Server

  setup do
    Phoenix.PubSub.subscribe(EzagentCore.PubSub, Server.topic())
    # Clear any prior state by unregistering known IDs the test creates.
    on_exit(fn ->
      Server.list_connected()
      |> Enum.each(fn {id, _} -> Server.unregister(id) end)
    end)

    :ok
  end

  test "register/2 records a bridge and broadcasts :cc_connected" do
    :ok = Server.register("test-bridge-1", %{claude_info: %{"name" => "test"}, tools: []})

    assert_receive {:cc_connected, "test-bridge-1", _entry}, 500
    assert Server.count() >= 1

    [{_, entry} | _] =
      Server.list_connected() |> Enum.filter(fn {id, _} -> id == "test-bridge-1" end)

    assert entry.info.claude_info == %{"name" => "test"}
  end

  test "unregister/1 removes the bridge and broadcasts :cc_disconnected" do
    :ok = Server.register("test-bridge-2", %{claude_info: %{}, tools: []})
    assert_receive {:cc_connected, "test-bridge-2", _}, 500

    :ok = Server.unregister("test-bridge-2")
    assert_receive {:cc_disconnected, "test-bridge-2"}, 500

    refute Enum.any?(Server.list_connected(), fn {id, _} -> id == "test-bridge-2" end)
  end

  test "status/0 reports {:connected, n} when bridges present, :no_bridges when empty" do
    # Start clean — unregister any existing.
    Server.list_connected() |> Enum.each(fn {id, _} -> Server.unregister(id) end)
    assert Server.status() == :no_bridges

    :ok = Server.register("status-test", %{claude_info: %{}, tools: []})
    assert {:connected, n} = Server.status()
    assert n >= 1
  end
end
