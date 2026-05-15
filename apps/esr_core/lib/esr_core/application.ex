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
      {Phoenix.PubSub, name: EsrCore.PubSub}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: EsrCore.Supervisor)
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
