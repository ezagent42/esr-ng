defmodule Ezagent.AppSettings do
  @moduledoc """
  Username & Auth M2 — key-value runtime config facade over the
  `app_settings` table. JSON-encodes values.

  Keys in use:
  - `"smtp_config"` — `%{"host","port","username","password","from_address","tls"}`
  - `"registration_domains"` — list of allowed email domains for new registration

  Both keys are written by the admin SMTP-settings UI (Phase 8). This
  module is the backend interface that UI calls.
  """

  use Ecto.Schema
  alias EzagentCore.Repo

  @primary_key {:key, :string, autogenerate: false}
  schema "app_settings" do
    field(:value, :string)
    timestamps(type: :utc_datetime_usec)
  end

  @smtp_required ~w(host port username password from_address)

  @doc "Decoded value for `key`, or `nil` if unset / unparseable."
  @spec get(String.t()) :: term() | nil
  def get(key) when is_binary(key) do
    case Repo.get(__MODULE__, key) do
      %__MODULE__{value: json} when is_binary(json) ->
        case Jason.decode(json) do
          {:ok, term} -> term
          _ -> nil
        end

      _ ->
        nil
    end
  end

  @doc "Upsert `key` with a JSON-encodable `term`. Returns `:ok`."
  @spec put(String.t(), term()) :: :ok
  def put(key, term) when is_binary(key) do
    json = Jason.encode!(term)

    %__MODULE__{}
    |> Ecto.Changeset.change(%{key: key, value: json})
    |> Repo.insert!(
      on_conflict: [set: [value: json, updated_at: DateTime.utc_now()]],
      conflict_target: :key
    )

    :ok
  end

  @doc "True only when `smtp_config` exists with every required field non-empty."
  @spec smtp_configured?() :: boolean()
  def smtp_configured? do
    case get("smtp_config") do
      %{} = cfg -> Enum.all?(@smtp_required, &present?(Map.get(cfg, &1)))
      _ -> false
    end
  end

  defp present?(v) when is_binary(v), do: String.trim(v) != ""
  defp present?(v) when is_integer(v), do: true
  defp present?(_), do: false
end
