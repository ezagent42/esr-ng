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

      # ⑦ Workspace DynamicSupervisor (Phase 4b) — holds spawned
      # `workspace://<name>` Kinds. Phase 4c's Loader queries the
      # `workspaces` table at app start and dispatches spawn_workspace
      # per row.
      {DynamicSupervisor, name: Esr.Workspace.Supervisor, strategy: :one_for_one}
    ]

    result = Supervisor.start_link(children, strategy: :one_for_one, name: EsrCore.Supervisor)

    # Attach telemetry handlers after the writer is up. Idempotent on restart.
    :ok = Esr.Audit.attach()

    # Phase 4b: register Workspace Behavior. Workspace is foundational
    # enough to live in esr_core (cross-plugin Entity, like User), so its
    # K-path wiring happens here rather than in a plugin Application.
    :ok = register_workspace_behavior()

    result
  end

  defp register_workspace_behavior do
    alias Esr.BehaviorRegistry
    alias Esr.Behavior.Workspace, as: WB
    alias Esr.Entity.Workspace, as: WK

    Enum.each(WB.actions(), fn action ->
      :ok = BehaviorRegistry.register(WK, action, WB)
    end)

    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
