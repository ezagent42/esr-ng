defmodule Esr.Workspace do
  @moduledoc """
  Workspace facade — spawn + query + durable mutation helpers.

  Phase 4b: `spawn_workspace/2` for in-memory Workspace Kinds.
  Phase 4c: `create/2` (persist + spawn), `add_member/2` etc. (persist
  + dispatch), `Loader` at app start.

  ## Durable mutation contract

  Mutation helpers (`add_member`, `remove_member`, `add_template`,
  `remove_template`, `set_routing_rules`) perform two writes:
  1. `Esr.Workspace.Store.update_*` — durable
  2. `Invocation.dispatch(:<action>, ...)` — live Kind

  Both succeed atomically per call (no transaction across them yet —
  Phase 5 may wrap in a single transactional path). The DB write is
  first so a crash between (1) and (2) at most leaves a Workspace in
  DB that doesn't match the live Kind for one boot — Loader resyncs on
  next start.

  Read paths (`list_members`, `list_templates`, etc.) go through the
  live Kind only; the DB is the recovery snapshot, not the read source.
  """

  alias Esr.Entity.Workspace, as: WK
  alias Esr.{Invocation, KindRegistry, Workspace.Store}

  # --- spawn ---------------------------------------------------------

  @doc """
  Spawn a Workspace Kind at `workspace://<name>` with the given
  initial slice args. In-memory only — use `create/2` for durable.
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

  # --- durable create -----------------------------------------------

  @doc """
  Persist a new Workspace + spawn its Kind. Use this from mix tasks /
  LV — `spawn_workspace/2` alone gives an ephemeral Workspace that
  vanishes on restart.

  `attrs` shape matches `Esr.Workspace.Store.create/2`.
  """
  @spec create(String.t(), map()) :: {:ok, pid()} | {:error, term()}
  def create(name, attrs \\ %{}) when is_binary(name) and name != "" do
    with {:ok, _decoded} <- Store.create(name, attrs),
         {:ok, pid} <- spawn_workspace(name, attrs) do
      {:ok, pid}
    end
  end

  # --- durable mutations --------------------------------------------

  @doc """
  Add `member_uri` to Workspace `name`. Writes to DB then dispatches
  `:add_member` on the live Workspace Kind so subsequent `list_members`
  returns the new member.
  """
  @spec add_member(String.t(), URI.t()) :: :ok | {:error, term()}
  def add_member(name, %URI{} = member_uri) do
    case Store.get_by_name(name) do
      nil ->
        {:error, :not_found}

      %{members: existing} ->
        new_members = Enum.uniq([member_uri | existing])

        with {:ok, _} <- Store.update_members(name, new_members),
             :ok <- dispatch_mutation(name, "add_member", %{member: member_uri}) do
          :ok
        end
    end
  end

  @spec remove_member(String.t(), URI.t()) :: :ok | {:error, term()}
  def remove_member(name, %URI{} = member_uri) do
    case Store.get_by_name(name) do
      nil ->
        {:error, :not_found}

      %{members: existing} ->
        new_members = Enum.reject(existing, &(URI.to_string(&1) == URI.to_string(member_uri)))

        with {:ok, _} <- Store.update_members(name, new_members),
             :ok <- dispatch_mutation(name, "remove_member", %{member: member_uri}) do
          :ok
        end
    end
  end

  @spec add_template(String.t(), String.t(), map()) :: :ok | {:error, term()}
  def add_template(name, tmpl_name, tmpl) when is_binary(tmpl_name) and is_map(tmpl) do
    case Store.get_by_name(name) do
      nil ->
        {:error, :not_found}

      %{session_templates: tmpls} ->
        new_tmpls = Map.put(tmpls, tmpl_name, tmpl)

        with {:ok, _} <- Store.update_templates(name, new_tmpls),
             :ok <-
               dispatch_mutation(name, "add_template", %{name: tmpl_name, template: tmpl}) do
          :ok
        end
    end
  end

  @spec remove_template(String.t(), String.t()) :: :ok | {:error, term()}
  def remove_template(name, tmpl_name) when is_binary(tmpl_name) do
    case Store.get_by_name(name) do
      nil ->
        {:error, :not_found}

      %{session_templates: tmpls} ->
        new_tmpls = Map.delete(tmpls, tmpl_name)

        with {:ok, _} <- Store.update_templates(name, new_tmpls),
             :ok <- dispatch_mutation(name, "remove_template", %{name: tmpl_name}) do
          :ok
        end
    end
  end

  @spec set_routing_rules(String.t(), [map()]) :: :ok | {:error, term()}
  def set_routing_rules(name, rules) when is_list(rules) do
    case Store.get_by_name(name) do
      nil ->
        {:error, :not_found}

      _ ->
        with {:ok, _} <- Store.update_routing_rules(name, rules),
             :ok <- dispatch_mutation(name, "set_routing_rules", %{rules: rules}) do
          :ok
        end
    end
  end

  defp dispatch_mutation(name, action_str, args) do
    target = URI.parse("workspace://#{name}/behavior/workspace/#{action_str}")

    case Invocation.dispatch(%Invocation{
           target: target,
           mode: :cast,
           args: args,
           ctx: %{
             caller: Esr.Entity.User.admin_uri(),
             caps: Esr.Entity.User.admin_caps(),
             reply: :ignore
           }
         }) do
      :ok -> :ok
      {:ok, _} -> :ok
      err -> err
    end
  end

  # --- listing -------------------------------------------------------

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

  @doc "List persisted Workspaces (decoded structs from `Esr.Workspace.Store`)."
  @spec list_persisted() :: [map()]
  def list_persisted, do: Store.list_all()
end
