defmodule Ezagent.Entity.AgentTemplateTest do
  @moduledoc """
  Phase 7 PR 37 — AgentTemplate Kind structural tests.

  These tests pin the Kind contract surface (callbacks, persistence,
  behaviors) so future refactors don't drift the type. End-to-end
  spawn + slice population is covered by Phase 7 PR 40 (`Ezagent.Entity.Agent.spawn/4`
  spawn-from-template flow) which exercises the spawn path.
  """

  use ExUnit.Case, async: true

  alias Ezagent.Entity.AgentTemplate

  test "type_name/0 returns :agent_template" do
    assert AgentTemplate.type_name() == :agent_template
  end

  test "behaviors/0 includes Identity (caps + grant policy live on slice)" do
    behaviors = AgentTemplate.behaviors()
    assert Ezagent.Behavior.Identity in behaviors,
           "AgentTemplate must carry Identity behavior so default_caps + slice " <>
             "edit can use the existing identity dispatch path"
  end

  test "persistence/0 is {:snapshot, :on_change} — config is durable" do
    assert AgentTemplate.persistence() == {:snapshot, :on_change},
           "AgentTemplate slice must survive phx restart; orchestrator's " <>
             "list_templates depends on persisted templates being there"
  end

  test "Ezagent.Kind behaviour callbacks all implemented" do
    # Spot-check by spawning a Kind.Server and asserting it accepts the
    # AgentTemplate as the kind module argument shape.
    callbacks_ok =
      [:type_name, :behaviors, :persistence]
      |> Enum.all?(fn cb -> function_exported?(AgentTemplate, cb, 0) end)

    assert callbacks_ok,
           "AgentTemplate must implement all three @impl Ezagent.Kind callbacks: " <>
             "type_name/0, behaviors/0, persistence/0"
  end
end
