defmodule Esr.Orchestrator.ToolsTest do
  @moduledoc """
  Phase 7 PR 46 — invariant test gating the 7 orchestrator MCP tool
  surface (SPEC §7-3 + Decision #141 "no fork tool — fork is
  SessionTemplate registry op").

  Bodies are stubs (`{:error, :not_implemented_yet}`) — full
  implementation lands in follow-up PRs once integration testing
  alongside the orchestrator's MCP server is set up. This PR locks
  the tool surface so future PRs can't silently add an 8th tool that
  grants more authority than the locked design.
  """

  use ExUnit.Case, async: true

  alias Esr.Orchestrator.Tools

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

  test "orchestrator does NOT have a `grant_cap` tool (PR 46 narrow scope)" do
    # Cap grants happen via Generator's scoped-delegation pattern
    # (Decision #137) — the orchestrator gets bounded caps from the
    # Generator at spawn time and uses THOSE to act. It doesn't have
    # an open-ended `grant_cap` tool that could escalate authority.
    refute Tools.tool?(:grant_cap),
           "Orchestrator MUST NOT have a `grant_cap` tool — that would open the " <>
             "delegation door to arbitrary authority grants. Cap delegation happens " <>
             "via scope-tuple caps Generator grants at spawn (Decision #137)."
  end

  test "each declared tool has an implementation (even if stub)" do
    for tool_name <- Tools.tool_names() do
      assert function_exported?(Tools, tool_name, 0) or
               function_exported?(Tools, tool_name, 1) or
               function_exported?(Tools, tool_name, 2) or
               function_exported?(Tools, tool_name, 3),
             "Tool #{inspect(tool_name)} is declared in tool_names/0 but has no " <>
               "corresponding function — declaration without implementation is a " <>
               "contract violation"
    end
  end

  test "invoke/2 dispatches by tool name; unknown tools surface :unknown_tool error" do
    assert {:error, {:unknown_tool, :totally_made_up}} =
             Tools.invoke(:totally_made_up, [])
  end

  test "invoke/2 reaches the stub for a known tool" do
    # All stubs return :not_implemented_yet — verify the dispatch
    # path reaches them (so when bodies are filled in, the dispatch
    # is already wired).
    assert {:error, :not_implemented_yet} = Tools.invoke(:list_templates, [])
    assert {:error, :not_implemented_yet} = Tools.invoke(:update_template, [])
  end
end
