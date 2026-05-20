defmodule Ezagent.IdentityTest do
  use EzagentCore.DataCase, async: false

  describe "list_caps_for/1" do
    test "returns empty MapSet for not-yet-spawned user" do
      uri = URI.parse("entity://user/never-spawned-#{System.unique_integer([:positive])}")
      caps = Ezagent.Identity.list_caps_for(uri)
      assert %MapSet{} = caps
      assert MapSet.size(caps) == 0
    end

    test "returns admin's all-cap MapSet for live admin Kind" do
      # Admin User is spawned at chat plugin Application.start with admin_caps
      caps = Ezagent.Identity.list_caps_for(Ezagent.Entity.User.admin_uri())

      assert MapSet.size(caps) >= 1

      assert Enum.any?(caps, fn cap ->
               cap.kind == :any and cap.behavior == :any and cap.instance == :any
             end)
    end
  end

  describe "admin?/1 (Phase 8c PR-F)" do
    test "returns true for the seeded admin URI (struct form)" do
      assert Ezagent.Identity.admin?(Ezagent.Entity.User.admin_uri())
    end

    test "returns true for the seeded admin URI (string form)" do
      assert Ezagent.Identity.admin?("entity://user/admin")
    end

    test "returns false for a non-admin user URI" do
      refute Ezagent.Identity.admin?("entity://user/alice")
      refute Ezagent.Identity.admin?(URI.parse("entity://user/bob"))
    end

    test "returns false for an agent URI" do
      refute Ezagent.Identity.admin?("entity://agent/claude-1")
    end

    test "returns false for nil" do
      refute Ezagent.Identity.admin?(nil)
    end

    test "returns false for a malformed URI string" do
      refute Ezagent.Identity.admin?("not a uri")
      refute Ezagent.Identity.admin?("")
    end

    test "returns false for any other input type" do
      refute Ezagent.Identity.admin?(:admin)
      refute Ezagent.Identity.admin?(42)
    end
  end
end
