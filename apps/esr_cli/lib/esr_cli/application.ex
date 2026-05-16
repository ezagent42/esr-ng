defmodule EsrCLI.Application do
  @moduledoc """
  EsrCLI Application — owns the `EsrCLI.FacadeRegistry` ETS table.

  No other children; the CLI itself is a one-shot mix task that builds
  its tree on each invocation.
  """

  use Application

  @impl true
  def start(_type, _args) do
    EsrCLI.FacadeRegistry.init_table()
    register_core_facade_ops()
    Supervisor.start_link([], strategy: :one_for_one, name: EsrCLI.Supervisor)
  end

  # CLI facade ops for operations that aren't Behavior actions.
  # Currently:
  # - workspace create — spawns a Workspace Kind (no instance exists
  #   yet to invoke an action on)
  defp register_core_facade_ops do
    EsrCLI.FacadeRegistry.register(:workspace, :create, &workspace_create_facade/1, %{
      args: [name: :string],
      opts: [members: {:list, :uri}],
      about: "Create a new Workspace (persists + spawns the Kind)"
    })

    :ok
  end

  defp workspace_create_facade(parsed) do
    name = parsed.args[:name]
    members = parsed.options[:members] || []

    case Esr.Workspace.create(name, %{members: members}) do
      {:ok, _pid} ->
        {:ok, %{name: name, uri: "workspace://#{name}", members: length(members)}}

      err ->
        err
    end
  end
end
