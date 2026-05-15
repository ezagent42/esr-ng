defmodule Esr.Entity.AgentTest do
  use ExUnit.Case, async: true
  alias Esr.Entity.Agent

  describe "Esr.Kind contract" do
    test "type_name/0 returns :agent" do
      assert Agent.type_name() == :agent
    end

    test "behaviors/0 returns [Esr.Behavior.Chat]" do
      assert Agent.behaviors() == [Esr.Behavior.Chat]
    end

    test "persistence/0 is :ephemeral" do
      assert Agent.persistence() == :ephemeral
    end
  end
end
