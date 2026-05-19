defmodule EzagentCore.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # ① ETS tables — must be ready before any process that reads/writes them
      # (KindRegistry, Idempotency.Sweeper, plugin Kind instances).
      # See DECISIONS impl-time §ETS+Application children.
      EzagentCore.EtsOwner,

      # ② stdlib Registry for URI → pid (Ezagent.KindRegistry wraps this).
      {Registry, keys: :unique, name: Ezagent.KindRegistry},

      # ③ Idempotency LRU prune — its own GenServer so a crash doesn't
      # take the ETS owner with it.
      Ezagent.Idempotency.Sweeper,

      # ④ SQLite repo + migrations (Phase 0 baseline).
      EzagentCore.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:ezagent_core, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:ezagent_core, :dns_cluster_query) || :ignore},

      # ⑤ PubSub — needed by LiveView audit:stream + future view fan-outs.
      {Phoenix.PubSub, name: EzagentCore.PubSub},

      # ⑥ Audit batch writer — must come after Repo + PubSub.
      Ezagent.Audit.Writer,

      # ⑦ Snapshot async writer (Phase 4-completion Spec 04) — handles
      # `:periodic` strategy; `:on_change` / `:on_terminate` go through
      # `Ezagent.Kind.Snapshot.save_now/3` synchronously.
      Ezagent.Snapshot.Writer,

      # ⑧ Foundation singleton supervisor — Phase 6 PR 2. Hosts core
      # singletons (System Kind sentinels + future cross-domain
      # controllers). Workspace.Supervisor moved out to
      # ezagent_domain_workspace as part of the three-layer split.
      {DynamicSupervisor, name: Ezagent.Core.SingletonSupervisor, strategy: :one_for_one}
    ]

    result = Supervisor.start_link(children, strategy: :one_for_one, name: EzagentCore.Supervisor)

    # Attach telemetry handlers after the writer is up. Idempotent on restart.
    :ok = Ezagent.Audit.attach()

    # PR #146 (SPEC v2 §5.7) — synthetic singleton `routing-admin://default`
    # dissolved. `Ezagent.Behavior.Routing` is registered against the
    # scope-owning Kinds (Workspace + Session + System) in their respective
    # domain Applications and here for System. Global rules dispatch to
    # `system://routing/default`, spawned below.
    :ok = register_system_kind()

    # Post-Phase-5 (Allen 2026-05-17): start distributed Erlang as the
    # named runtime node so `mix esr` (CLI) can reach us via :rpc.call.
    # Cookie + node name from Ezagent.Runtime. Skip in test env to avoid
    # interfering with ExUnit's own process tree.
    if not is_test?() do
      :ok = Ezagent.Runtime.configure_for_runtime!()
    end

    result
  end

  defp is_test? do
    Code.ensure_loaded?(Mix) and Mix.env() == :test
  rescue
    _ -> false
  end

  # PR #146 — register Routing Behavior on the System Kind, spawn the
  # canonical global-rules sentinel `system://routing/default`, and
  # register a SpawnRegistry fn for the `system://` scheme so future
  # sentinels (`system://bootstrap/default`, `system://migration-<id>`)
  # spawn through the standard SpawnRegistry path.
  defp register_system_kind do
    alias Ezagent.BehaviorRegistry
    alias Ezagent.Behavior.Routing, as: RB
    alias Ezagent.Entity.System, as: SK

    Enum.each(RB.actions(), fn action ->
      :ok = BehaviorRegistry.register(SK, action, RB)
    end)

    :ok =
      Ezagent.SpawnRegistry.register("system", fn %URI{} = uri ->
        DynamicSupervisor.start_child(
          Ezagent.Core.SingletonSupervisor,
          {Ezagent.Kind.Server, {SK, %{uri: uri}}}
        )
      end)

    uri = SK.routing_default_uri()

    case Ezagent.KindRegistry.lookup(uri) do
      {:ok, _pid} ->
        :ok

      :error ->
        case Ezagent.SpawnRegistry.spawn(uri) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          err -> err
        end
    end
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
