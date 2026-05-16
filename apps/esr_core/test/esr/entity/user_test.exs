defmodule Esr.Entity.UserTest do
  use ExUnit.Case, async: true
  alias Esr.Entity.User
  alias Esr.Capability

  test "admin_uri/0 returns user://admin" do
    uri = User.admin_uri()
    assert %URI{} = uri
    assert uri.scheme == "user"
    assert uri.host == "admin"
  end

  test "admin_caps/0 returns a MapSet containing exactly the structural all-caps cap" do
    caps = User.admin_caps()
    assert %MapSet{} = caps
    assert MapSet.size(caps) == 1

    [cap] = MapSet.to_list(caps)
    assert cap.kind == :any
    assert cap.behavior == :any
    assert cap.instance == :any
    assert cap.granted_by.scheme == "system"
    assert cap.granted_by.host == "bootstrap"
  end

  test "admin_caps cap matches any invocation" do
    [cap] = MapSet.to_list(User.admin_caps())

    assert Capability.matches?(cap, %{
             kind: :random,
             behavior: SomeMod,
             instance: URI.parse("agent://anything")
           })
  end

  test "admin_caps cap is refused by revoke/2" do
    [admin_cap] = MapSet.to_list(User.admin_caps())
    caps = User.admin_caps()
    assert {:error, :cannot_revoke_admin} = Capability.revoke(caps, admin_cap)
  end

  test "Kind callbacks return Phase 3d values (Identity behavior added)" do
    assert User.type_name() == :user
    assert User.behaviors() == [Esr.Behavior.Identity]
    assert User.persistence() == {:snapshot, :on_change}
  end
end
