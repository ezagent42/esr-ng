defmodule EsrCore.EtsOwner do
  @moduledoc """
  EtsOwner — owns the lifecycle of ETS tables for the ETS-backed
  reliability primitives.

  Per DECISIONS implementation-decision §ETS table owner — Option B:
  one GenServer holds all tables, reducing supervisor noise and
  giving a single restart point that recreates every table together.
  Phase 1 owns: `:esr_ready_gate`, `:esr_pending_delivery`,
  `:esr_idempotency`, `:esr_behavior_registry`. The stdlib `Registry`
  for `Esr.KindRegistry` is its own supervisor child (different
  lifecycle shape).

  ## Boot order invariant (DECISIONS impl-time §ETS+Application children)

  This GenServer **must** start before any process that touches the
  tables — `Esr.KindRegistry` Registry, `Esr.Idempotency.Sweeper`,
  plugin Echo's default instance spawn, etc. Children order in
  `EsrCore.Application` puts this first.

  ## Recovery semantics

  If the owner crashes, `:public` tables die with it. Supervisor
  restart recreates them empty. State stored in these tables is
  ephemeral by design (ReadyGate / PendingDelivery / Idempotency
  are all "what's in flight right now"; reset on restart is
  acceptable). Persistent state lives in SQLite via `Esr.Kind.Snapshot`.
  """

  use GenServer

  @tables [
    {Esr.ReadyGate, :set},
    {Esr.PendingDelivery, :set},
    {Esr.Idempotency, :set},
    {Esr.BehaviorRegistry, :set},
    {Esr.RoutingRegistry, :set}
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
