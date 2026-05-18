defmodule Ezagent.Behavior.EchoTest do
  use ExUnit.Case, async: true
  alias Ezagent.Behavior.Echo

  test "interface declares :say with :string args + returns" do
    iface = Echo.interface()
    assert %{say: %{args: %{msg: :string}, returns: %{echo: :string}, modes: modes}} = iface
    assert :call in modes
    assert :cast in modes
  end

  test "actions/0 returns [:say]" do
    assert Echo.actions() == [:say]
  end

  test "state_slice/0 is :echo" do
    assert Echo.state_slice() == :echo
  end

  test "init_slice/1 returns %{count: 0, last_msg: nil}" do
    assert Echo.init_slice(%{}) == %{count: 0, last_msg: nil}
  end

  test "invoke/4 echoes msg and increments count" do
    slice = Echo.init_slice(%{})

    assert {:ok, new_slice, %{echo: "hello"}} = Echo.invoke(:say, slice, %{msg: "hello"}, %{})
    assert new_slice.count == 1
    assert new_slice.last_msg == "hello"
  end

  test "invoke chains — count keeps incrementing" do
    s0 = Echo.init_slice(%{})
    {:ok, s1, _} = Echo.invoke(:say, s0, %{msg: "a"}, %{})
    {:ok, s2, _} = Echo.invoke(:say, s1, %{msg: "b"}, %{})

    assert s2.count == 2
    assert s2.last_msg == "b"
  end
end
