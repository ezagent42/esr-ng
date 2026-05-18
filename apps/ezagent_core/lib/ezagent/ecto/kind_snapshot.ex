defmodule Ezagent.Ecto.KindSnapshot do
  @moduledoc """
  Ecto schema for `kind_snapshots` (Phase 4-completion Spec 04).

  Schema layout:
  - `uri` — primary key (one row per Kind instance)
  - `kind_type` — stable type atom per Decision #62
  - `state_binary` — `:erlang.term_to_binary/1` of the full slice map
    (lossless for MapSet / URI / DateTime / atoms)
  - `state` — legacy JSON column (Phase 1 / 5+ drop); kept for
    read-side fallback during the transition
  - `version` — schema version per Spec 04 §2.G
  - `inserted_at` / `updated_at`

  Writes go to `state_binary`; reads prefer `state_binary` then fall
  back to legacy `state` so the upgrade path is seamless.
  """

  use Ecto.Schema
  import Ecto.Query

  alias EzagentCore.Repo

  @primary_key {:uri, :string, autogenerate: false}
  schema "kind_snapshots" do
    field :kind_type, :string
    field :state_binary, :binary
    field :state, :map
    field :version, :integer, default: 0
    field :inserted_at, :utc_datetime_usec
    field :updated_at, :utc_datetime_usec
  end

  @doc """
  Fetch a single snapshot row by URI. Returns the Ecto schema struct or nil.
  """
  @spec get(String.t()) :: %__MODULE__{} | nil
  def get(uri_str) when is_binary(uri_str), do: Repo.get(__MODULE__, uri_str)

  @doc """
  List all snapshot rows (for `/admin/snapshots` LV + `mix ezagent.snapshot.list`).
  Ordered by `updated_at` desc so most-recently-active Kinds appear first.
  """
  @spec list_all() :: [%__MODULE__{}]
  def list_all do
    from(s in __MODULE__, order_by: [desc: s.updated_at])
    |> Repo.all()
  end

  @doc """
  Upsert (insert or update) the snapshot for `uri_str`.
  """
  @spec upsert(String.t(), String.t(), binary(), non_neg_integer()) ::
          {:ok, %__MODULE__{}} | {:error, term()}
  def upsert(uri_str, kind_type_str, binary, version)
      when is_binary(uri_str) and is_binary(kind_type_str) and is_binary(binary) and
             is_integer(version) do
    now = DateTime.utc_now()

    attrs = %{
      uri: uri_str,
      kind_type: kind_type_str,
      state_binary: binary,
      # Keep state as nil for new rows; legacy rows may have JSON
      version: version,
      updated_at: now
    }

    case Repo.get(__MODULE__, uri_str) do
      nil ->
        %__MODULE__{}
        |> Ecto.Changeset.change(Map.put(attrs, :inserted_at, now))
        |> Repo.insert()

      existing ->
        existing
        |> Ecto.Changeset.change(attrs)
        |> Repo.update()
    end
  end

  @doc "Delete the snapshot for `uri_str`. Returns `:ok` even if nothing existed."
  @spec delete(String.t()) :: :ok
  def delete(uri_str) when is_binary(uri_str) do
    from(s in __MODULE__, where: s.uri == ^uri_str) |> Repo.delete_all()
    :ok
  end

  @doc """
  Decode the snapshot's state map. Prefers `state_binary` (`term_to_binary`,
  lossless); falls back to legacy `state` (JSON). Returns `:error` if both
  are nil/empty.

  Uses `:safe` flag on `binary_to_term` to reject unknown atoms.
  """
  @spec decode_state(%__MODULE__{}) :: {:ok, map()} | {:error, term()}
  def decode_state(%__MODULE__{state_binary: bin}) when is_binary(bin) and byte_size(bin) > 0 do
    try do
      term = :erlang.binary_to_term(bin, [:safe])

      if is_map(term) do
        {:ok, term}
      else
        {:error, {:not_a_map, term}}
      end
    rescue
      ArgumentError -> {:error, :unsafe_atom}
    end
  end

  def decode_state(%__MODULE__{state: state}) when is_map(state), do: {:ok, state}
  def decode_state(%__MODULE__{}), do: :error
end
