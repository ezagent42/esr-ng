defmodule Esr.Entity.SessionTest do
  use ExUnit.Case, async: true
  alias Esr.Entity.Session

  describe "Esr.Kind contract" do
    test "type_name/0 returns :session" do
      assert Session.type_name() == :session
    end

    test "behaviors/0 returns [Esr.Behavior.Chat]" do
      assert Session.behaviors() == [Esr.Behavior.Chat]
    end

    test "persistence/0 is :ephemeral" do
      assert Session.persistence() == :ephemeral
    end
  end

  describe "default_uri/0" do
    test "returns session://main as a %URI{} struct" do
      uri = Session.default_uri()
      assert %URI{scheme: "session", host: "main"} = uri
    end
  end
end
