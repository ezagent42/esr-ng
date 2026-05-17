defmodule EsrCore.Application do
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
      EsrCore.EtsOwner,

      # ② stdlib Registry for URI → pid (Esr.KindRegistry wraps this).
      {Registry, keys: :unique, name: Esr.KindRegistry},

      # ③ Idempotency LRU prune — its own GenServer so a crash doesn't
      # take the ETS owner with it.
      Esr.Idempotency.Sweeper,

      # ④ SQLite repo + migrations (Phase 0 baseline).
      EsrCore.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:esr_core, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:esr_core, :dns_cluster_query) || :ignore},

      # ⑤ PubSub — needed by LiveView audit:stream + future view fan-outs.
      {Phoenix.PubSub, name: EsrCore.PubSub},

      # ⑥ Audit batch writer — must come after Repo + PubSub.
      Esr.Audit.Writer,

      # ⑦ Snapshot async writer (Phase 4-completion Spec 04) — handles
      # `:periodic` strategy; `:on_change` / `:on_terminate` go through
      # `Esr.Kind.Snapshot.save_now/3` synchronously.
      Esr.Snapshot.Writer,

      # ⑧ Foundation singleton supervisor — Phase 6 PR 2. Hosts core
      # singletons (RoutingAdmin and future cross-domain controllers).
      # Workspace.Supervisor moved out to esr_domain_workspace as part
      # of the three-layer split.
      {DynamicSupervisor, name: Esr.Core.SingletonSupervisor, strategy: :one_for_one}
    ]

    result = Supervisor.start_link(children, strategy: :one_for_one, name: EsrCore.Supervisor)

    # Attach telemetry handlers after the writer is up. Idempotent on restart.
    :ok = Esr.Audit.attach()

    # Phase 5 PR 4: register RoutingAdmin Behavior + spawn singleton
    # `routing-admin://default` so /admin/routing dispatches go through
    # CapBAC check at step 5.5. Workspace registration moved to
    # esr_domain_workspace.Application in Phase 6 PR 2.
    :ok = register_routing_admin()

    # Post-Phase-5 (Allen 2026-05-17): start distributed Erlang as the
    # named runtime node so `mix esr` (CLI) can reach us via :rpc.call.
    # Cookie + node name from Esr.Runtime. Skip in test env to avoid
    # interfering with ExUnit's own process tree.
    if not is_test?() do
      :ok = Esr.Runtime.configure_for_runtime!()
    end

    result
  end

  defp is_test? do
    Code.ensure_loaded?(Mix) and Mix.env() == :test
  rescue
    _ -> false
  end

  defp register_routing_admin do
    alias Esr.BehaviorRegistry
    alias Esr.Behavior.RoutingAdmin, as: RAB
    alias Esr.Entity.RoutingAdmin, as: RAK

    Enum.each(RAB.actions(), fn action ->
      :ok = BehaviorRegistry.register(RAK, action, RAB)
    end)

    uri = RAK.default_uri()

    case Esr.KindRegistry.lookup(uri) do
      {:ok, _pid} ->
        :ok

      :error ->
        case DynamicSupervisor.start_child(
               Esr.Core.SingletonSupervisor,
               {Esr.Kind.Server, {RAK, %{uri: uri}}}
             ) do
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
