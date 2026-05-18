defmodule Ezagent.Entity.AgentTest do
  use ExUnit.Case, async: true
  alias Ezagent.Entity.Agent

  describe "Ezagent.Kind contract" do
    test "type_name/0 returns :agent" do
      assert Agent.type_name() == :agent
    end

    test "behaviors/0 returns [Ezagent.Behavior.Chat, Ezagent.Behavior.Identity]" do
      assert Agent.behaviors() == [Ezagent.Behavior.Chat, Ezagent.Behavior.Identity]
    end

    test "persistence/0 is :on_terminate (Phase 4-completion Spec 04 §2.I)" do
      assert Agent.persistence() == :on_terminate
    end
  end
end
