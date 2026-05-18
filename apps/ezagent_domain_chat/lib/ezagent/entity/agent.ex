defmodule Ezagent.Entity.Agent do
  @moduledoc """
  Agent Kind — represents an external participant (e.g. a Claude CLI
  session via the CC bridge) inside ESR's chat router.

  Per Decision #61: an Agent is a peer of admin User in the Session —
  it can send messages (when its bridge surfaces a reply) and receive
  messages (forwarded by Session). The Agent Kind itself owns the
  bridge mapping and routes the cross-process traffic — see
  `Ezagent.Bridge.V1Prototype.Server` for the wire side.

  ## Spawn lifecycle

  Phase 2 does NOT spawn any Agent at boot. Agent Kinds materialize
  when a bridge announces itself:

      Bridge announce (HTTP POST /announce)
        → Ezagent.CcBridgeAnnounceController.announce/2
        → DynamicSupervisor.start_child(EzagentDomainChat.AgentSupervisor,
            {Ezagent.Kind.Server, {Ezagent.Entity.Agent, %{uri: agent_uri}}})

  This is the realization of memory `feedback_north_star_plugin_isolation`:
  the Agent module knows nothing about bridges; the controller knows
  nothing about Chat. The DynamicSupervisor + Ezagent.Kind.Server are the
  only contact points, and they're both `ezagent_core` machinery.

  ## URI shape

  Bridges supply `agent_uri` either via the mcp.json `env` field
  (preferred — PtyServer writes it deterministically) or via
  `EZAGENT_AGENT_URI` operator-shell env (legacy fallback). Anything
  matching `agent://*` works at the routing layer.
  """

  @behaviour Ezagent.Kind

  @impl Ezagent.Kind
  def type_name, do: :agent

  # Phase 3d: Agent carries Identity Behavior alongside Chat. Default
  # initial_caps is empty (Agent has no authority to initiate; chat
  # receive only). Operators can grant caps via Identity invoke if
  # they want to elevate a specific Agent.
  @impl Ezagent.Kind
  def behaviors, do: [Ezagent.Behavior.Chat, Ezagent.Behavior.Identity]

  # Phase 4-completion Spec 04: `:on_terminate` so granted Identity
  # caps survive graceful shutdown. Abrupt crash still loses them
  # (bridge re-announce re-creates Agent fresh; acceptable). Bump to
  # `:on_change` in Phase 5 once Agent caps see real promotion volume.
  @impl Ezagent.Kind
  def persistence, do: :on_terminate

  @doc """
  Phase 7 PR 40 — Spawn a worker agent from an AgentTemplate.

  Composes existing primitives without introducing a new spawn
  contract: builds the instance Agent URI, calls
  `Ezagent.SpawnRegistry.spawn/1` (URI-only per Decision #65), then
  records lineage in `Ezagent.WorkspaceRegistry` for workspace scope +
  `Ezagent.AgentLineage` for `{:spawned_by, _}` cap resolution (PR 42
  / Decision #137).

  ## Args

  - `template_uri` — `template://agent/<template_name>` (must
    be an already-registered AgentTemplate Kind)
  - `instance_name` — string, becomes the instance Agent URI's
    host segment (`agent://<instance_name>`). Caller's job to
    ensure uniqueness; collisions return
    `{:error, {:already_started, _}}` per SpawnRegistry semantics.
  - `workspace_uri` — `%URI{}` scope this Agent belongs to;
    bound via `Ezagent.WorkspaceRegistry.bind/2` so workspace-scoped
    routing rules apply (invariant 4 per esr-developer skill).
  - `granted_by` — `%URI{}` of the principal authorizing the spawn
    (orchestrator URI in the typical case). Recorded in
    `Ezagent.AgentLineage` to support `{:spawned_by, granted_by}`
    scoped delegation caps.

  ## Return

  `{:ok, agent_uri}` on success, `{:error, reason}` on spawn or
  lineage-record failure. Lineage failure (registry not started)
  is logged but not fatal — the agent spawns successfully and
  loses lineage tracking only.

  ## What this PR does NOT do

  - Does NOT instantiate the underlying claude process (PtyServer
    spawns that on bridge announce). AgentTemplate's
    `working_directory` / `claude_config_dir` / `settings_path`
    are consumed by the PR 32 v2 bridge / PtyServer integration —
    Agent.spawn/4 is the ESR-side Kind registration, not the
    PTY-side process spawn.
  - Does NOT populate AgentTemplate slice content from the
    template Kind (the template's slice is empty per PR 37 — admin
    populates it). Calling Agent.spawn/4 against an empty
    AgentTemplate produces an Agent with default settings (operator
    `~/.claude/`).
  """
  @spec spawn(
          template_uri :: URI.t(),
          instance_name :: String.t(),
          workspace_uri :: URI.t(),
          granted_by :: URI.t()
        ) :: {:ok, URI.t()} | {:error, term()}
  def spawn(%URI{} = _template_uri, instance_name, %URI{} = workspace_uri, %URI{} = granted_by)
      when is_binary(instance_name) do
    agent_uri = URI.new!("agent://#{instance_name}")

    with {:ok, _pid} <- spawn_or_resume(agent_uri),
         :ok <- Ezagent.WorkspaceRegistry.bind(agent_uri, workspace_uri),
         :ok <- record_lineage(agent_uri, granted_by) do
      {:ok, agent_uri}
    else
      err -> err
    end
  end

  defp spawn_or_resume(agent_uri) do
    case Ezagent.SpawnRegistry.spawn(agent_uri) do
      {:ok, _pid} = ok -> ok
      {:error, {:already_started, pid}} -> {:ok, pid}
      err -> err
    end
  end

  defp record_lineage(agent_uri, granted_by) do
    if Code.ensure_loaded?(Ezagent.AgentLineage) and function_exported?(Ezagent.AgentLineage, :record, 2) do
      Ezagent.AgentLineage.record(agent_uri, granted_by)
    else
      # AgentLineage registry not loaded — log + continue. PR 42's
      # {:spawned_by, _} cap shape returns false in this case, so
      # absence of lineage data degrades gracefully (no false grants).
      require Logger

      Logger.debug(
        "Ezagent.Entity.Agent.spawn: AgentLineage registry not loaded; " <>
          "{:spawned_by, _} cap shapes will deny for #{URI.to_string(agent_uri)}"
      )

      :ok
    end
  end
end
