defmodule EzagentCore.EtsOwner do
  @moduledoc """
  EtsOwner — owns the lifecycle of ETS tables for the ETS-backed
  reliability primitives.

  Per DECISIONS implementation-decision §ETS table owner — Option B:
  one GenServer holds all tables, reducing supervisor noise and
  giving a single restart point that recreates every table together.
  Phase 1 owns: `:ezagent_ready_gate`, `:ezagent_pending_delivery`,
  `:ezagent_idempotency`, `:ezagent_behavior_registry`. The stdlib `Registry`
  for `Ezagent.KindRegistry` is its own supervisor child (different
  lifecycle shape).

  ## Boot order invariant (DECISIONS impl-time §ETS+Application children)

  This GenServer **must** start before any process that touches the
  tables — `Ezagent.KindRegistry` Registry, `Ezagent.Idempotency.Sweeper`,
  plugin Echo's default instance spawn, etc. Children order in
  `EzagentCore.Application` puts this first.

  ## Recovery semantics

  If the owner crashes, `:public` tables die with it. Supervisor
  restart recreates them empty. State stored in these tables is
  ephemeral by design (ReadyGate / PendingDelivery / Idempotency
  are all "what's in flight right now"; reset on restart is
  acceptable). Persistent state lives in SQLite via `Ezagent.Kind.Snapshot`.
  """

  use GenServer

  @tables [
    {Ezagent.ReadyGate, :set},
    {Ezagent.PendingDelivery, :set},
    {Ezagent.Idempotency, :set},
    {Ezagent.BehaviorRegistry, :set},
    {Ezagent.RoutingRegistry, :set},
    {Ezagent.SpawnRegistry, :set},
    {Ezagent.TemplateRegistry, :set},
    # Phase 7 PR 31 (IMPL-7-1): session→workspace back-edge for
    # Ezagent.Behavior.Chat.invoke(:send) to plumb workspace_uri into
    # Resolver. See WorkspaceRegistry moduledoc.
    {Ezagent.WorkspaceRegistry, :set},
    # Phase 7 PR 40: agent spawn lineage for {:spawned_by, _} cap
    # shape (Decision #137 / PR 42). Ezagent.Entity.Agent.spawn/4
    # records here; CapBAC step 5.5 (future PR 46+) reads here.
    {Ezagent.AgentLineage, :set},
    # PR #141 (SPEC v2): agent flavor → spawn fn registry. Each plugin
    # registers its agent flavor (e.g. "cc", "curl", "echo") → spawn
    # fn; the chat plugin's `entity://` SpawnRegistry fn delegates here
    # for `host = "agent"`, extracting flavor from the URI's name
    # prefix `<flavor>_<rest>` (SPEC §5.14).
    {Ezagent.AgentTypeRegistry, :set}
  ]

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    Enum.each(@tables, fn {mod, type} ->
      :ets.new(mod.table(), [type, :public, :named_table, read_concurrency: true])
    end)

    {:ok, %{tables: Enum.map(@tables, fn {mod, _} -> mod.table() end)}}
  end
end
