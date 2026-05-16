defmodule Esr.Behavior.RoutingAdmin do
  @moduledoc """
  Phase 5 PR 4 — Behavior implementing routing rule mutations (Spec 5B
  Q-RT-3 synthetic Kind path).

  Actions:
  - `:add_rule` — args `%{table: atom, matcher_json: map, receivers: [String]}`
    → returns `%{id: integer}` (matcher_json decoded via `Matcher.from_json/1`
    inside invoke; pre-encoded so InterfaceValidator accepts it — tuples are
    rejected by the `:map` shape gate)
  - `:delete_rule` — args `%{id: integer}` → `:ok`(refuses system_default)
  - `:disable_rule` — args `%{id: integer}` → `:ok`
  - `:enable_rule` — args `%{id: integer}` → `:ok`

  Wraps `Esr.Routing.RuleStore` + automatically calls
  `RuleStore.load_into_registry(table)` after each mutation so the live
  RoutingRegistry ETS reflects the change immediately.

  Cap check fires at dispatch step 5.5 — caller needs a cap matching
  `kind: :routing_admin, behavior: Esr.Behavior.RoutingAdmin, instance: <routing-admin uri>`.
  Admin's triple-`:any` cap satisfies; non-admin without explicit
  grant gets `:unauthorized`.

  Slice: trivial counter (`%{calls: 0}`) — Kind state is just an
  audit counter for "how many mutations went through me". Snapshot
  `:ephemeral` (no need to persist the counter).
  """

  @behaviour Esr.Behavior

  alias Esr.Routing.{Matcher, RuleStore}

  @impl Esr.Behavior
  def actions, do: [:add_rule, :delete_rule, :disable_rule, :enable_rule]

  @impl Esr.Behavior
  def state_slice, do: :routing_admin

  @impl Esr.Behavior
  def init_slice(_args), do: %{calls: 0}

  @impl Esr.Behavior
  def invoke(:add_rule, slice, args, _ctx) do
    %{table: table, matcher_json: matcher_json, receivers: receivers} = args
    opts = Map.get(args, :opts, [])

    with {:ok, matcher} <- Matcher.from_json(matcher_json),
         {:ok, row} <- RuleStore.add(table, matcher, receivers, nil, opts) do
      :ok = RuleStore.load_into_registry(table)
      {:ok, bump(slice), %{id: row.id}}
    else
      {:error, _} = err -> err
      err -> {:error, err}
    end
  end

  def invoke(:delete_rule, slice, %{id: id} = args, _ctx) when is_integer(id) do
    table = Map.fetch!(args, :table)

    case RuleStore.delete(id) do
      :ok ->
        :ok = RuleStore.load_into_registry(table)
        {:ok, bump(slice), %{deleted: id}}

      err ->
        err
    end
  end

  def invoke(:disable_rule, slice, %{id: id} = args, _ctx) when is_integer(id) do
    table = Map.fetch!(args, :table)

    case RuleStore.disable(id) do
      :ok ->
        :ok = RuleStore.load_into_registry(table)
        {:ok, bump(slice), %{disabled: id}}

      err ->
        err
    end
  end

  def invoke(:enable_rule, slice, %{id: id} = args, _ctx) when is_integer(id) do
    table = Map.fetch!(args, :table)

    case RuleStore.enable(id) do
      :ok ->
        :ok = RuleStore.load_into_registry(table)
        {:ok, bump(slice), %{enabled: id}}

      err ->
        err
    end
  end

  defp bump(slice), do: %{slice | calls: slice.calls + 1}

  @impl Esr.Behavior
  def interface do
    %{
      add_rule: %{
        args: %{table: :atom, matcher_json: :map, receivers: {:list, :string}},
        returns: %{id: :integer},
        modes: [:call]
      },
      delete_rule: %{args: %{table: :atom, id: :integer}, returns: %{deleted: :integer}, modes: [:call]},
      disable_rule: %{args: %{table: :atom, id: :integer}, returns: %{disabled: :integer}, modes: [:call]},
      enable_rule: %{args: %{table: :atom, id: :integer}, returns: %{enabled: :integer}, modes: [:call]}
    }
  end

  @doc """
  Build the cap-needed shape for any RoutingAdmin action — useful for
  Identity.grant operations to grant the routing-modify cap to a user.
  """
  def required_cap_shape do
    %{
      kind: :routing_admin,
      behavior: __MODULE__,
      instance: Esr.Entity.RoutingAdmin.default_uri()
    }
  end
end
