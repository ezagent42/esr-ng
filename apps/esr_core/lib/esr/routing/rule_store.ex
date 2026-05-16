defmodule Esr.Routing.RuleStore do
  @moduledoc """
  SQLite-persisted routing rules (per P3-D10).

  Admin-created rules survive BEAM restart. Boot-time bootstrap
  inserts system-default rules idempotently (chat plugin's
  `bootstrap_default_rules/0` checks emptiness before inserting).

  ## Schema

  ```
  id            integer primary key
  table_name    string  (e.g. "EsrPluginChat.Routing.MentionRouting")
  matcher_data  text    (Jason-encoded matcher AST per Esr.Routing.Matcher.to_json/1)
  receivers     text    (Jason-encoded [String.t()] of receiver URIs)
  created_by    string  (URI of admin who added; nil for system-default)
  created_at    utc_datetime_usec
  ```

  ## API

  - `add(table_name_atom, matcher_tuple, receivers_list, created_by_uri)`
  - `list(table_name_atom) :: [rule_map()]`
  - `delete(id)`
  - `load_into_registry(table_name_atom)` — on boot, reads SQLite rules
    and puts them into the live `RoutingRegistry` ETS table

  Resolver reads the **ETS table** (not SQLite directly) — RuleStore
  is the persistence layer that hydrates ETS at boot.
  """

  use Ecto.Schema
  import Ecto.Query
  alias EsrCore.Repo

  @primary_key {:id, :id, autogenerate: true}
  schema "routing_rules" do
    field :table_name, :string
    field :matcher_data, :map
    field :receivers, {:array, :string}
    field :created_by, :string
    field :created_at, :utc_datetime_usec
  end

  @type t :: %__MODULE__{
          id: integer() | nil,
          table_name: String.t(),
          matcher_data: map(),
          receivers: [String.t()],
          created_by: String.t() | nil,
          created_at: DateTime.t() | nil
        }

  @doc """
  Insert a new rule. `matcher_tuple` is `Esr.Routing.Matcher.matcher()`,
  internally serialized via `to_json/1`. `receivers` is `[URI.t()]`
  or `[String.t()]`.
  """
  @spec add(atom(), Esr.Routing.Matcher.matcher(), [URI.t() | String.t()], URI.t() | nil) ::
          {:ok, t()} | {:error, term()}
  def add(table_name_atom, matcher_tuple, receivers, created_by) when is_atom(table_name_atom) do
    receivers_str = Enum.map(receivers, &uri_to_string/1)

    rule = %__MODULE__{
      table_name: Atom.to_string(table_name_atom),
      matcher_data: Esr.Routing.Matcher.to_json(matcher_tuple),
      receivers: receivers_str,
      created_by: uri_to_string_or_nil(created_by),
      created_at: DateTime.utc_now()
    }

    Repo.insert(rule)
  end

  @doc "List all rules for a given table (as Ecto schema rows)."
  @spec list(atom()) :: [t()]
  def list(table_name_atom) when is_atom(table_name_atom) do
    table_str = Atom.to_string(table_name_atom)

    from(r in __MODULE__,
      where: r.table_name == ^table_str,
      order_by: [asc: r.id]
    )
    |> Repo.all()
  end

  @doc """
  Bulk-load all rules for a table into the live `RoutingRegistry`.

  Called at boot by the owning plugin. Each row's matcher gets parsed
  back via `Matcher.from_json/1`. Bad rows are logged and skipped
  (don't crash plugin boot for one bad rule).
  """
  @spec load_into_registry(atom()) :: :ok
  def load_into_registry(table_name_atom) when is_atom(table_name_atom) do
    list(table_name_atom)
    |> Enum.each(fn row ->
      case Esr.Routing.Matcher.from_json(row.matcher_data) do
        {:ok, matcher_tuple} ->
          Esr.RoutingRegistry.put(table_name_atom, matcher_tuple, row.receivers)

        {:error, reason} ->
          require Logger
          Logger.error("RuleStore: skipping rule id=#{row.id} — bad matcher: #{inspect(reason)}")
      end
    end)

    :ok
  end

  @doc "Delete a rule by id."
  @spec delete(integer()) :: :ok | {:error, term()}
  def delete(id) when is_integer(id) do
    case Repo.get(__MODULE__, id) do
      nil ->
        {:error, :not_found}

      rule ->
        Repo.delete(rule)
        |> case do
          {:ok, _} -> :ok
          err -> err
        end
    end
  end

  defp uri_to_string(%URI{} = u), do: URI.to_string(u)
  defp uri_to_string(s) when is_binary(s), do: s

  defp uri_to_string_or_nil(nil), do: nil
  defp uri_to_string_or_nil(u), do: uri_to_string(u)
end
