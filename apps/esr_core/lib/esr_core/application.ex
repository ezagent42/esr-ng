defmodule EsrCore.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      EsrCore.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:esr_core, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:esr_core, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: EsrCore.PubSub}
      # Start a worker by calling: EsrCore.Worker.start_link(arg)
      # {EsrCore.Worker, arg}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: EsrCore.Supervisor)
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
