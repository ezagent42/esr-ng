defmodule Ezagent.Entity.MagicLinkToken do
  @moduledoc """
  Username & Auth M3 — single-use, 15-min magic-link tokens.

  `mint/2` returns the RAW token (goes in the email URL, never stored).
  Only SHA-256(raw) is persisted. `consume/2` is single-use: it stamps
  `consumed_at`, so a replayed link fails with `{:error, :consumed}`.
  """

  use Ecto.Schema
  import Ecto.Query
  alias EzagentCore.Repo

  @ttl_seconds 15 * 60

  schema "magic_link_tokens" do
    field(:email, :string)
    field(:token_hash, :binary)
    field(:expires_at, :utc_datetime_usec)
    field(:consumed_at, :utc_datetime_usec)
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @type t :: %__MODULE__{}

  @doc """
  Mint a token for `email`. Returns `{:ok, raw_token}`.

  Opts: `:ttl_seconds` (default 900; negative values produce an
  already-expired token, for tests).
  """
  @spec mint(String.t(), keyword()) :: {:ok, String.t()}
  def mint(email, opts \\ []) when is_binary(email) do
    raw = "esr_ml_" <> (:crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false))
    ttl = Keyword.get(opts, :ttl_seconds, @ttl_seconds)

    %__MODULE__{}
    |> Ecto.Changeset.change(%{
      email: String.downcase(String.trim(email)),
      token_hash: hash(raw),
      expires_at: DateTime.add(DateTime.utc_now(), ttl, :second)
    })
    |> Repo.insert!()

    {:ok, raw}
  end

  @doc """
  Consume `raw_token`. On success returns `{:ok, email}` and the token
  cannot be consumed again.

  Errors: `:invalid` (unknown), `:expired`, `:consumed`.
  """
  @spec consume(String.t()) :: {:ok, String.t()} | {:error, :invalid | :expired | :consumed}
  def consume(raw_token) when is_binary(raw_token) do
    case Repo.get_by(__MODULE__, token_hash: hash(raw_token)) do
      nil ->
        {:error, :invalid}

      %__MODULE__{consumed_at: %DateTime{}} ->
        {:error, :consumed}

      %__MODULE__{expires_at: exp} = row ->
        if DateTime.compare(DateTime.utc_now(), exp) == :gt do
          {:error, :expired}
        else
          row
          |> Ecto.Changeset.change(%{consumed_at: DateTime.utc_now()})
          |> Repo.update!()

          {:ok, row.email}
        end
    end
  end

  def consume(_), do: {:error, :invalid}

  @doc "Delete tokens minted before `cutoff`. Housekeeping."
  @spec prune(DateTime.t()) :: {non_neg_integer(), nil}
  def prune(cutoff) do
    from(t in __MODULE__, where: t.inserted_at < ^cutoff) |> Repo.delete_all()
  end

  defp hash(raw), do: :crypto.hash(:sha256, raw)
end
