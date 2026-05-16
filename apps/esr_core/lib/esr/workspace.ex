defmodule Esr.Workspace do
  @moduledoc """
  Workspace facade — convenience helpers for spawning + querying
  Workspace Kinds.

  Phase 4b: `spawn_workspace/2` starts a `workspace://<name>` Kind under
  the `Esr.Workspace.Supervisor` (a DynamicSupervisor declared in
  `EsrCore.Application`). The Kind enters `Esr.KindRegistry` so dispatch
  routes to it for every Workspace Behavior action.

  Phase 4c will add `Esr.Workspace.Loader` that queries the persisted
  `workspaces` table at app start and calls `spawn_workspace/2` per row.
  """

  alias Esr.Entity.Workspace, as: WK
  alias Esr.KindRegistry

  @doc """
  Spawn a Workspace Kind at `workspace://<name>` with the given
  initial slice args.

  Returns `{:ok, pid}` on success, `{:error, :already_started, pid}`
  if a Workspace at this URI is already alive, or the underlying
  Registry/Supervisor error.
  """
  @spec spawn_workspace(String.t(), map()) ::
          {:ok, pid()} | {:error, term()}
  def spawn_workspace(name, args \\ %{}) when is_binary(name) do
    uri = WK.uri_for(name)

    case KindRegistry.lookup(uri) do
      {:ok, pid} ->
        {:error, {:already_started, pid}}

      :error ->
        DynamicSupervisor.start_child(
          Esr.Workspace.Supervisor,
          {Esr.Kind.Server, {WK, Map.put(args, :uri, uri)}}
        )
    end
  end

  @doc """
  List all live Workspace URIs (those registered in KindRegistry under
  the `workspace://` scheme).
  """
  @spec list_workspaces() :: [URI.t()]
  def list_workspaces do
    KindRegistry.list_all()
    |> Enum.filter(fn {uri_str, _pid} -> String.starts_with?(uri_str, "workspace://") end)
    |> Enum.map(fn {uri_str, _pid} -> URI.parse(uri_str) end)
    |> Enum.sort_by(&URI.to_string/1)
  end
end
