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
      # singletons (RoutingAdmin and future cross-domain controllers).
      # Workspace.Supervisor moved out to ezagent_domain_workspace as part
      # of the three-layer split.
      {DynamicSupervisor, name: Ezagent.Core.SingletonSupervisor, strategy: :one_for_one}
    ]

    result = Supervisor.start_link(children, strategy: :one_for_one, name: EzagentCore.Supervisor)

    # Attach telemetry handlers after the writer is up. Idempotent on restart.
    :ok = Ezagent.Audit.attach()

    # Phase 5 PR 4: register RoutingAdmin Behavior + spawn singleton
    # `routing-admin://default` so /admin/routing dispatches go through
    # CapBAC check at step 5.5. Workspace registration moved to
    # ezagent_domain_workspace.Application in Phase 6 PR 2.
    :ok = register_routing_admin()

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

  defp register_routing_admin do
    alias Ezagent.BehaviorRegistry
    alias Ezagent.Behavior.RoutingAdmin, as: RAB
    alias Ezagent.Entity.RoutingAdmin, as: RAK

    Enum.each(RAB.actions(), fn action ->
      :ok = BehaviorRegistry.register(RAK, action, RAB)
    end)

    uri = RAK.default_uri()

    case Ezagent.KindRegistry.lookup(uri) do
      {:ok, _pid} ->
        :ok

      :error ->
        case DynamicSupervisor.start_child(
               Ezagent.Core.SingletonSupervisor,
               {Ezagent.Kind.Server, {RAK, %{uri: uri}}}
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
