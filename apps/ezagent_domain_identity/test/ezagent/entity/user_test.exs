defmodule Ezagent.Entity.UserTest do
  use ExUnit.Case, async: true
  alias Ezagent.Entity.User
  alias Ezagent.Capability

  test "admin_uri/0 returns entity://user/admin" do
    uri = User.admin_uri()
    assert %URI{} = uri
    assert uri.scheme == "entity"
    assert uri.host == "user"
    assert uri.path == "/admin"
  end

  test "admin_caps/0 returns a MapSet containing exactly the structural all-caps cap" do
    caps = User.admin_caps()
    assert %MapSet{} = caps
    assert MapSet.size(caps) == 1

    [cap] = MapSet.to_list(caps)
    assert cap.kind == :any
    assert cap.behavior == :any
    assert cap.instance == :any
    # PR #141 SPEC v2 §5.1: system://bootstrap → system://bootstrap/default
    assert cap.granted_by.scheme == "system"
    assert cap.granted_by.host == "bootstrap"
    assert cap.granted_by.path == "/default"
  end

  test "admin_caps cap matches any invocation" do
    [cap] = MapSet.to_list(User.admin_caps())

    assert Capability.matches?(cap, %{
             kind: :random,
             behavior: SomeMod,
             instance: URI.parse("entity://agent/test_anything")
           })
  end

  test "admin_caps cap is refused by revoke/2" do
    [admin_cap] = MapSet.to_list(User.admin_caps())
    caps = User.admin_caps()
    assert {:error, :cannot_revoke_admin} = Capability.revoke(caps, admin_cap)
  end

  test "Kind callbacks return Phase 3d values (Identity behavior added) + PR #126 ApiKeys" do
    assert User.type_name() == :user
    assert User.behaviors() == [Ezagent.Behavior.Identity, Ezagent.Behavior.ApiKeys]
    assert User.persistence() == {:snapshot, :on_change}
  end

  describe "default_caps/0 (PR 27)" do
    test "includes a kind=:session cap so every user can attempt session behaviors" do
      caps = User.default_caps()

      assert is_list(caps)

      assert Enum.any?(caps, fn c ->
               c.kind == :session and c.behavior == :any and c.instance == :any
             end),
             "expected a session:any:any cap in default_caps, got: #{inspect(caps)}"
    end

    test "default caps are granted_by system://bootstrap (structural, not human-issued)" do
      for cap <- User.default_caps() do
        assert cap.granted_by.scheme == "system"
        assert cap.granted_by.host == "bootstrap"
      end
    end

    test "default_caps does NOT include the admin wildcard" do
      refute Enum.any?(User.default_caps(), fn c ->
               c.kind == :any and c.behavior == :any and c.instance == :any
             end),
             "default_caps must not grant the admin escape hatch to ordinary users"
    end
  end
end
