defmodule EzagentCli.FacadeRegistry do
  @moduledoc """
  Per-kind facade operations registry — for ops that aren't Behavior
  actions (because they create/find Kinds rather than mutating slice
  state on an existing one).

  Mirror of `Ezagent.SpawnRegistry` + `Ezagent.TemplateRegistry` pattern:
  plugin Application.start registers facade ops; CLI walks both
  `BehaviorRegistry` (real actions) + this registry (facade ops) when
  building its subcommand tree.

  ## API

      EzagentCli.FacadeRegistry.register(:workspace, :create, &MyPlugin.create_workspace/1, %{
        args: [name: :string],
        opts: [members: {:list, :uri}],
        about: "Create a new Workspace"
      })

  Plugin ops are 1-arg fns taking a parsed-args map (from Optimus). They
  return `{:ok, term}` or `{:error, reason}`. CLI's formatter handles
  the rest.
  """

  @table :ezagent_cli_facade_registry

  def table, do: @table

  def init_table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])

      _ ->
        :ok
    end

    :ok
  end

  @doc """
  Register a facade op for the given `kind_type` (atom matching the
  Kind module's `type_name/0`) — or `nil` for facade-only kinds (e.g.
  `:routing` has no `routing://` Kind, only ops).

  `spec`:
  - `:args` — positional args (keyword `[name: :string]`)
  - `:opts` — named options (keyword `[members: {:list, :uri}]`)
  - `:about` — help text
  """
  @spec register(atom() | nil, atom(), function(), map()) :: :ok
  def register(kind_type, op_name, fun, spec)
      when (is_atom(kind_type) or is_nil(kind_type)) and is_atom(op_name) and is_function(fun, 1) and
             is_map(spec) do
    init_table()
    :ets.insert(@table, {{kind_type, op_name}, fun, spec})
    :ok
  end

  @doc "List facade ops for one kind (or `nil` for facade-only-kinds)."
  @spec list(atom() | nil) :: [{atom(), function(), map()}]
  def list(kind_type) when is_atom(kind_type) or is_nil(kind_type) do
    init_table()

    :ets.tab2list(@table)
    |> Enum.filter(fn {{kt, _op}, _fun, _spec} -> kt == kind_type end)
    |> Enum.map(fn {{_kt, op}, fun, spec} -> {op, fun, spec} end)
    |> Enum.sort_by(fn {op, _fun, _spec} -> op end)
  end

  @doc "List all kind_types that have at least one facade op registered."
  @spec list_kinds() :: [atom() | nil]
  def list_kinds do
    init_table()

    :ets.tab2list(@table)
    |> Enum.map(fn {{kt, _op}, _fun, _spec} -> kt end)
    |> Enum.uniq()
    |> Enum.sort_by(&to_string(&1 || ""))
  end

  @doc "Look up a single facade op."
  @spec lookup(atom() | nil, atom()) :: {:ok, function(), map()} | :error
  def lookup(kind_type, op_name) do
    init_table()

    case :ets.lookup(@table, {kind_type, op_name}) do
      [{_, fun, spec}] -> {:ok, fun, spec}
      [] -> :error
    end
  end
end
