defmodule Esr.IdentityTest do
  use EsrCore.DataCase, async: false

  describe "list_caps_for/1" do
    test "returns empty MapSet for not-yet-spawned user" do
      uri = URI.parse("user://never-spawned-#{System.unique_integer([:positive])}")
      caps = Esr.Identity.list_caps_for(uri)
      assert %MapSet{} = caps
      assert MapSet.size(caps) == 0
    end

    test "returns admin's all-cap MapSet for live admin Kind" do
      # Admin User is spawned at chat plugin Application.start with admin_caps
      caps = Esr.Identity.list_caps_for(Esr.Entity.User.admin_uri())

      assert MapSet.size(caps) >= 1

      assert Enum.any?(caps, fn cap ->
               cap.kind == :any and cap.behavior == :any and cap.instance == :any
             end)
    end
  end
end
