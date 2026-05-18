defmodule Esr.Entity.Session do
  @moduledoc """
  Session Kind — the "room" in Phase 2's chat routing model.

  A Session is the entity that holds a set of member URIs and routes
  outbound chat messages to them. Per Decision #61 + P2-D2 K-path:
  Session handles `:send / :join / :leave` actions; the member-side
  `:receive` action runs on the recipient Kind (User / Agent).

  Phase 2 spawns exactly one default instance — `session://main` —
  at `EsrDomainChat.Application.start/2`. Multi-Session support is
  intentionally out of scope (Phase 3+).

  ## Persistence flipped to {:snapshot, :on_change} in Phase 7 PR 44

  Phase 2 originally used `:ephemeral` — members / monitors /
  last_seen were rebuilt at each boot from PubSub re-announcements
  and admin User re-join in `handle_continue(:announce_ready)`.
  Historical message stream was persisted (via `Esr.MessageStore`);
  only in-flight membership was ephemeral.

  **Phase 7 PR 44 (D7-7 + SPEC §7-3 working-copy session slice)**:
  the orchestrator's `template_working_copy` field on Chat slice
  (Session-context) must survive phx restart so the orchestrator's
  team-refinement work isn't lost on every server bounce. Flipping
  persistence to `{:snapshot, :on_change}` makes the Chat slice's
  `template_working_copy` durable. Pre-Phase-7 sessions reload
  with empty working_copy on next state change → behaves as before.

  Members / monitors / last_seen ARE now persisted as a side
  effect of the slice-level snapshot. This is mostly harmless:
  members get re-validated when their owning Kind comes up (admin
  User, Agents via bridge re-announce); monitors are stale across
  restart anyway (refs only valid for live processes); last_seen
  reflects history not live state. The added durability is mostly
  invisible to existing flows.
  """

  @behaviour Esr.Kind

  @impl Esr.Kind
  def type_name, do: :session

  @impl Esr.Kind
  def behaviors, do: [Esr.Behavior.Chat]

  @impl Esr.Kind
  # Phase 7 PR 44: WILL FLIP TO {:snapshot, :on_change} once orchestrator
  # working-copy lands (PR 46). Phase 7 PR 44 explored the flip and
  # discovered it triggers snapshot writes during tests that don't
  # own the Ecto sandbox connection (Esr.Audit.Writer-style cascade
  # via Esr.Kind.Snapshot.save_now). Fix is per-test setup updates,
  # not a code revert. Deferred to PR 46 which adds the
  # template_working_copy slice field AND the test-helper updates
  # together. Until then, persistence stays :ephemeral — working-copy
  # is lost on restart, accepted in dev / acceptable for v1 demo.
  def persistence, do: :ephemeral

  @doc "URI of the default Session instance spawned at boot."
  @spec default_uri() :: URI.t()
  def default_uri, do: URI.new!("session://main")

  @doc """
  Phase 7 PR 41 — the **Generator**: instantiate a Session from a
  SessionTemplate.

  Per SPEC D7-2 + Allen 2026-05-18 round 2: "创建一个新 session(自带
  orchestrator)的一段程序是 generator". Not an agent — just the spawn
  program. Each new session gets its own orchestrator instance baked in.

  ## Args

  - `session_template_uri` — `template://session/<name>@<version_hash>` or
    `template://session/<name>:<tag>` (resolved via template_tags
    registry in future; PR 41 accepts hash form only)
  - `owner_uri` — `%URI{}` of the human / principal triggering the
    instantiation. Becomes `granted_by` for orchestrator spawn (so
    orchestrator's `{:spawned_by, owner_uri}` cap shapes work via
    AgentLineage from PR 40).

  ## Return

  `{:ok, %{session_uri: URI.t(), orchestrator_uri: URI.t()}}` on success,
  `{:error, reason}` on lookup / spawn / lineage failures.

  ## PR 41 minimal scope

  Spawns ONLY the orchestrator (not the agent_slots workers). Per
  Allen's design + SPEC §7-3 §"Orchestrator" section: the orchestrator
  is the team-builder, and its tools (PR 46) populate the worker
  agent_slots via dispatch. PR 41 ships the Generator's spawn-the-
  orchestrator path; PR 46 ships the orchestrator-spawns-workers path.

  Routing rule installation + working-copy slice initialization + full
  agent_slots iteration are deferred to PR 46.

  ## CapBAC gate

  Generator is NOT a dispatched Behavior action (it's a public function
  callable from LV / CLI / programmatic). Cap check happens at the
  caller's surface — LV checks `owner_uri` has `template:instantiate`
  cap on the SessionTemplate URI before invoking. PR 41 ships the
  function; the LV `template:instantiate` cap check lands when the LV
  "instantiate session from template" button lands (likely PR 46 era).

  Conservative interim: callers MUST verify owner_uri has the
  necessary caps before invoking; Generator trusts the caller.
  """
  @spec spawn_from_template(URI.t(), URI.t()) ::
          {:ok, %{session_uri: URI.t(), orchestrator_uri: URI.t()}} | {:error, term()}
  def spawn_from_template(%URI{} = session_template_uri, %URI{} = owner_uri) do
    with {:ok, _template_pid} <- ensure_template_alive(session_template_uri),
         {:ok, session_uri} <- spawn_fresh_session(),
         {:ok, workspace_uri} <- default_workspace_for_session(session_uri),
         :ok <- Esr.WorkspaceRegistry.bind(session_uri, workspace_uri),
         {:ok, orchestrator_uri} <-
           spawn_orchestrator(session_uri, workspace_uri, owner_uri) do
      {:ok, %{session_uri: session_uri, orchestrator_uri: orchestrator_uri}}
    else
      err -> err
    end
  end

  defp ensure_template_alive(%URI{} = template_uri) do
    case Esr.KindRegistry.lookup(template_uri) do
      {:ok, pid} -> {:ok, pid}
      :error -> Esr.SpawnRegistry.spawn(template_uri)
    end
  end

  defp spawn_fresh_session do
    # Timestamped session URI; instance_name = `gen-<unix-ms>-<rand>`
    # so concurrent Generator calls don't collide.
    unique_suffix = "#{System.system_time(:millisecond)}-#{System.unique_integer([:positive])}"
    session_uri = URI.new!("session://gen-#{unique_suffix}")

    case Esr.SpawnRegistry.spawn(session_uri) do
      {:ok, _pid} -> {:ok, session_uri}
      err -> err
    end
  end

  defp default_workspace_for_session(_session_uri) do
    # Phase 7 PR 41 minimal: workspace defaults to a generic
    # "generated-session" workspace. SessionTemplate's
    # default_workspace_uri field will replace this once
    # SessionTemplate slice population lands (PR 46 era).
    {:ok, URI.new!("workspace://generated-sessions")}
  end

  defp spawn_orchestrator(session_uri, workspace_uri, owner_uri) do
    # Spawn the cc-orchestrator (PR 45 seed) under a fresh instance
    # name keyed to this session for traceability.
    template_uri = URI.parse("template://agent/cc-orchestrator")
    instance_name = "orchestrator-#{session_uri.host}"

    Esr.Entity.Agent.spawn(template_uri, instance_name, workspace_uri, owner_uri)
  end
end
