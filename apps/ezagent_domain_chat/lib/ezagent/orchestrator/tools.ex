defmodule Ezagent.Orchestrator.Tools do
  @moduledoc """
  Orchestrator MCP tool surface — declares the 7 tools the
  cc-orchestrator (Decision #136, SPEC §7-3) exposes to the LLM
  it hosts.

  ## The 7 tools

  Per SPEC §"7 orchestration tools" (Phase 7 PR 46):

  | Tool | Args | Effect |
  |---|---|---|
  | `add_agent_slot` | slot_name, agent_template_uri, optional prompt_override | Spawns a worker agent from template; adds to working-copy `agent_slots` |
  | `remove_agent_slot` | slot_name | Despawns the worker, drops from working-copy |
  | `update_agent_template` | slot_name, new_agent_template_uri | Replaces an agent slot's template (re-spawn) |
  | `write_matcher` | matcher_ast, receiver_slot_names | Inserts routing rule into runtime + working-copy |
  | `update_template` | (no args) | Commit working copy as NEW VERSION of current parent template; requires `template:write` cap |
  | `save_template_as` | new_name | Commit working copy as FIRST version of NEW template; requires template-creation cap |
  | `list_templates` | optional name_filter | Returns available AgentTemplate + SessionTemplate URIs caller can see per CapBAC |

  ## PR 46 scope (this PR — minimal interface declaration)

  Ships the **tool surface declaration** + structural test gating the
  7 tools list. Each tool is currently a stub returning
  `{:error, :not_implemented_yet}`. Implementation of each tool
  body — calling into `Ezagent.Entity.Agent.spawn/4` (PR 40),
  `Ezagent.Entity.SessionTemplate.compute_version_hash/1` (PR 38),
  `Ezagent.Routing.RuleStore.add/5`, etc — lands in follow-up PRs
  47-49 (Generator scoped grant + in-flight deletion + e2e demo)
  + a future "PR 46-impl" once Allen's design feedback on the
  exact MCP tool argument schemas is in.

  This PR's value:
  - Locks the tool surface (7 tools, named, with arg shapes per SPEC)
  - Codifies the design lock that orchestrator does NOT have a `fork`
    tool (fork is SessionTemplate registry operation, per Decision #141)
  - CI gate ensures the 7 tools stay 7 (future PR can't silently add
    an 8th tool that grants more authority than the locked design)

  ## Why an `Ezagent.Orchestrator.Tools` module instead of `Ezagent.Behavior.Orchestrator`

  The orchestrator's tools are MCP tools (claude-side), not ESR
  Behaviors (dispatch-side). They live in this module as plain
  functions that the orchestrator's MCP server invokes. Each tool
  internally dispatches via `Ezagent.Invocation.dispatch/1` to do the
  actual work (e.g. `add_agent_slot` dispatches `agent/spawn` via
  the Agent Kind's eventual Behavior, or directly calls
  `Ezagent.Entity.Agent.spawn/4`).
  """

  require Logger

  @doc "The 7 orchestration tool names. CI gate test pins this list at 7."
  @spec tool_names() :: [atom()]
  def tool_names do
    [
      :add_agent_slot,
      :remove_agent_slot,
      :update_agent_template,
      :write_matcher,
      :update_template,
      :save_template_as,
      :list_templates
    ]
  end

  @doc "True iff `name` is one of the 7 declared orchestration tools."
  @spec tool?(atom()) :: boolean()
  def tool?(name) when is_atom(name), do: name in tool_names()
  def tool?(_), do: false

  # --- tool stubs (PR 46 ships signatures; bodies in follow-up PRs) ---

  def add_agent_slot(_slot_name, _agent_template_uri, _prompt_override \\ nil),
    do: {:error, :not_implemented_yet}

  def remove_agent_slot(_slot_name), do: {:error, :not_implemented_yet}

  def update_agent_template(_slot_name, _new_agent_template_uri),
    do: {:error, :not_implemented_yet}

  def write_matcher(_matcher_ast, _receiver_slot_names),
    do: {:error, :not_implemented_yet}

  def update_template, do: {:error, :not_implemented_yet}

  def save_template_as(_new_name), do: {:error, :not_implemented_yet}

  def list_templates(_name_filter \\ nil), do: {:error, :not_implemented_yet}

  @doc """
  Generic tool invocation entry point — dispatches by tool name to
  the corresponding function above. Returns `{:error,
  {:unknown_tool, name}}` for non-listed names (CI gate against
  silently-added tools).
  """
  @spec invoke(atom(), list()) :: {:ok, term()} | {:error, term()}
  def invoke(tool_name, args) when is_atom(tool_name) and is_list(args) do
    if tool?(tool_name) do
      apply(__MODULE__, tool_name, args)
    else
      {:error, {:unknown_tool, tool_name}}
    end
  end
end
