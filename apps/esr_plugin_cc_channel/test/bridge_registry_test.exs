defmodule EsrPluginCcChannel.BridgeRegistryTest do
  use ExUnit.Case, async: false

  alias EsrPluginCcChannel.BridgeRegistry

  setup do
    BridgeRegistry.init()
    # Clean slate
    for {uri, _pid} <- BridgeRegistry.list_all() do
      BridgeRegistry.unbind(uri)
    end

    :ok
  end

  test "bind / lookup / unbind roundtrip" do
    uri = URI.new!("agent://test-bridge-#{System.unique_integer([:positive])}")
    pid = spawn(fn -> Process.sleep(:infinity) end)

    assert :ok = BridgeRegistry.bind(uri, pid)
    assert {:ok, ^pid} = BridgeRegistry.lookup(uri)
    assert :ok = BridgeRegistry.unbind(uri)
    assert :error = BridgeRegistry.lookup(uri)
  end

  test "double-bind same pid is idempotent" do
    uri = URI.new!("agent://test-bridge-double")
    pid = spawn(fn -> Process.sleep(:infinity) end)

    :ok = BridgeRegistry.bind(uri, pid)
    assert :ok = BridgeRegistry.bind(uri, pid)
  end

  test "bind on top of live pid returns :already_bound" do
    uri = URI.new!("agent://test-bridge-conflict")
    p1 = spawn(fn -> Process.sleep(:infinity) end)
    p2 = spawn(fn -> Process.sleep(:infinity) end)

    :ok = BridgeRegistry.bind(uri, p1)
    assert {:error, :already_bound} = BridgeRegistry.bind(uri, p2)
  end

  test "bind replaces a dead pid silently" do
    uri = URI.new!("agent://test-bridge-replace")
    p1 = spawn(fn -> :ok end)
    Process.sleep(20)
    refute Process.alive?(p1)

    :ok = BridgeRegistry.bind(uri, p1)
    p2 = spawn(fn -> Process.sleep(:infinity) end)
    assert :ok = BridgeRegistry.bind(uri, p2)
    assert {:ok, ^p2} = BridgeRegistry.lookup(uri)
  end
end
