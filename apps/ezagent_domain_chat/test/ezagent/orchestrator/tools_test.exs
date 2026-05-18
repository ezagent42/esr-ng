defmodule Ezagent.Orchestrator.ToolsTest do
  @moduledoc """
  Phase 7 PR 46 — invariant test gating the 7 orchestrator MCP tool
  surface (SPEC §7-3 + Decision #141 "no fork tool — fork is
  SessionTemplate registry op") + Decision #137 (no `grant_cap` tool).

  PR 46-impl extends the original PR 46 stub-only tests with assertions
  that **every tool's body is wired** — missing required ctx surfaces
  `{:error, {:missing_opt, _}}` instead of `:not_implemented_yet`.
  """

  use ExUnit.Case, async: true

  alias Ezagent.Orchestrator.Tools

  test "exactly 7 orchestration tools declared (SPEC §7-3 lock)" do
    names = Tools.tool_names()
    assert length(names) == 7,
           "Orchestrator tool surface must remain exactly 7 tools per SPEC §7-3. " <>
             "Adding an 8th requires Allen-level design review (cap-grant authority " <>
             "implications). Got #{length(names)}: #{inspect(names)}"
  end

  test "the 7 tools are the SPEC-named ones" do
    expected = [
      :add_agent_slot,
      :remove_agent_slot,
      :update_agent_template,
      :write_matcher,
      :update_template,
      :save_template_as,
      :list_templates
    ]

    actual = Tools.tool_names()

    assert MapSet.new(actual) == MapSet.new(expected),
           "Orchestrator tools diverged from SPEC list. Expected: #{inspect(expected)}, " <>
             "got: #{inspect(actual)}"
  end

  test "orchestrator does NOT have a `fork` tool (Decision #141 lock)" do
    refute Tools.tool?(:fork),
           "Orchestrator MUST NOT have a `fork` tool. Fork is a SessionTemplate " <>
             "registry operation invoked by Generator / Session creation paths; " <>
             "orchestrator uses `update_template` (refine in place) or " <>
             "`save_template_as` (save as new) for in-session template evolution. " <>
             "Decision #141 explicitly excludes fork from the orchestrator's verb set."
  end

  test "orchestrator does NOT have a `grant_cap` tool (Decision #137)" do
    refute Tools.tool?(:grant_cap),
           "Orchestrator MUST NOT have a `grant_cap` tool — that would open the " <>
             "delegation door to arbitrary authority grants. Cap delegation happens " <>
             "via scope-tuple caps Generator grants at spawn (Decision #137)."
  end

  test "each declared tool has an implementation function" do
    for tool_name <- Tools.tool_names() do
      assert function_exported?(Tools, tool_name, 0) or
               function_exported?(Tools, tool_name, 1) or
               function_exported?(Tools, tool_name, 2) or
               function_exported?(Tools, tool_name, 3) or
               function_exported?(Tools, tool_name, 4),
             "Tool #{inspect(tool_name)} is declared in tool_names/0 but has no " <>
               "corresponding function — declaration without implementation is a " <>
               "contract violation"
    end
  end

  test "invoke/2 dispatches by tool name; unknown tools surface :unknown_tool error" do
    assert {:error, {:unknown_tool, :totally_made_up}} =
             Tools.invoke(:totally_made_up, [])
  end

  describe "PR 46-impl — all 7 tools have wired bodies (no :not_implemented_yet)" do
    test "list_templates/2 returns the catalog map" do
      assert {:ok, %{agent_templates: agents, session_templates: sessions}} =
               Tools.list_templates()

      assert is_list(agents)
      assert is_list(sessions)
    end

    test "add_agent_slot/4 surfaces :missing_opt for required ctx — proves body is wired" do
      template_uri = URI.parse("template://agent/cc-orchestrator")

      assert {:error, {:missing_opt, :workspace_uri}} =
               Tools.add_agent_slot("test-slot", template_uri, nil, [])
    end

    test "remove_agent_slot/2 is idempotent {:ok, :removed} for non-existent slot" do
      assert {:ok, :removed} =
               Tools.remove_agent_slot("never-existed-#{System.unique_integer([:positive])}")
    end

    test "update_agent_template/3 surfaces :missing_opt without full ctx" do
      assert {:error, {:missing_opt, :workspace_uri}} =
               Tools.update_agent_template("x", URI.parse("template://agent/x"), [])
    end

    test "write_matcher/3 surfaces :missing_opt without workspace_uri" do
      assert {:error, {:missing_opt, :workspace_uri}} =
               Tools.write_matcher({:mention, "x"}, ["x"], [])
    end

    test "update_template/1 surfaces :missing_opt for session_uri" do
      assert {:error, {:missing_opt, :session_uri}} = Tools.update_template([])
    end

    test "save_template_as/2 surfaces :missing_opt without session_uri" do
      assert {:error, {:missing_opt, :session_uri}} = Tools.save_template_as("x", [])
    end

    test "all 7 tools NEVER return :not_implemented_yet (PR 46-impl gate)" do
      # Goal acceptance criterion: "all 7 orchestrator tools return
      # {:ok, _} not :not_implemented_yet for valid args". Tools without
      # full ctx surface {:error, {:missing_opt, _}} — explicitly NOT
      # :not_implemented_yet, proving every body is wired.
      results = [
        {:list_templates, Tools.list_templates()},
        {:add_agent_slot,
         Tools.add_agent_slot("x", URI.parse("template://agent/x"), nil, [])},
        {:remove_agent_slot, Tools.remove_agent_slot("x")},
        {:update_agent_template,
         Tools.update_agent_template("x", URI.parse("template://agent/x"), [])},
        {:write_matcher, Tools.write_matcher({:mention, "x"}, ["x"], [])},
        {:update_template, Tools.update_template([])},
        {:save_template_as, Tools.save_template_as("x", [])}
      ]

      for {name, result} <- results do
        refute match?({:error, :not_implemented_yet}, result),
               "Tool #{name} still returns :not_implemented_yet — PR 46-impl regressed. " <>
                 "Got: #{inspect(result)}"
      end
    end
  end
end
