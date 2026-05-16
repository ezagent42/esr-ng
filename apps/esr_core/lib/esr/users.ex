defmodule Esr.Users do
  @moduledoc """
  Facade for the `users` SQLite table — provisioning + login lookup
  (Phase 4-completion Spec 05 Part A).

  Distinct from User-Kind snapshot:
  - `users` is **provisioning config** — "these credentials exist, here
    are their initial caps."
  - User Kind's `:identity` slice is **runtime state** — "the live cap
    set, possibly mutated by ops."

  Boot flow: plugin Application.start reads `users.list_all/0` → for
  each row, spawns the User Kind via SpawnRegistry with `initial_caps:`
  decoded from `caps_json`.

  Per Spec 05 Q-MU-4: passwords are bcrypt-hashed via `:bcrypt_elixir`.
  """

  use Ecto.Schema
  import Ecto.Query
  alias EsrCore.Repo

  @primary_key {:id, :id, autogenerate: true}
  schema "users" do
    field :uri, :string
    field :password_hash, :string
    field :caps_json, :string
    timestamps(type: :utc_datetime_usec)
  end

  @type decoded :: %{
          id: integer() | nil,
          uri: URI.t(),
          password_hash: String.t() | nil,
          caps: [Esr.Capability.t()]
        }

  # --- write paths ---------------------------------------------------

  @doc """
  Create a new User row. `password` is bcrypt-hashed before insert.
  Caps are `[Esr.Capability.t()]` — serialized via Jason.
  """
  @spec create(URI.t() | String.t(), String.t() | nil, [Esr.Capability.t()]) ::
          {:ok, decoded()} | {:error, term()}
  def create(uri, password, caps) when is_list(caps) do
    uri_str = uri_to_str(uri)

    hash =
      if is_binary(password) and password != "" do
        Bcrypt.hash_pwd_salt(password)
      else
        nil
      end

    changeset =
      %__MODULE__{}
      |> Ecto.Changeset.change(%{
        uri: uri_str,
        password_hash: hash,
        caps_json: encode_caps(caps)
      })
      |> Ecto.Changeset.unique_constraint(:uri, name: :users_uri_index)

    case Repo.insert(changeset) do
      {:ok, row} -> {:ok, decode(row)}
      err -> err
    end
  end

  @doc "Set or rotate a user's password. Returns `{:ok, decoded}` or `{:error, :not_found}`."
  @spec set_password(URI.t() | String.t(), String.t()) ::
          {:ok, decoded()} | {:error, term()}
  def set_password(uri, password) when is_binary(password) and password != "" do
    uri_str = uri_to_str(uri)
    hash = Bcrypt.hash_pwd_salt(password)

    case Repo.get_by(__MODULE__, uri: uri_str) do
      nil ->
        {:error, :not_found}

      row ->
        row
        |> Ecto.Changeset.change(%{password_hash: hash})
        |> Repo.update()
        |> case do
          {:ok, updated} -> {:ok, decode(updated)}
          err -> err
        end
    end
  end

  @doc "Verify a password against the stored hash. Returns true/false."
  @spec verify_password(URI.t() | String.t(), String.t()) :: boolean()
  def verify_password(uri, password) when is_binary(password) do
    uri_str = uri_to_str(uri)

    case Repo.get_by(__MODULE__, uri: uri_str) do
      %__MODULE__{password_hash: hash} when is_binary(hash) and hash != "" ->
        Bcrypt.verify_pass(password, hash)

      _ ->
        # No row OR password_hash is NULL — refuse login. Per Spec 05
        # Q-MU-1: admin must set password via mix task before first login.
        # Run a dummy verification to avoid timing leak.
        Bcrypt.no_user_verify()
        false
    end
  end

  # --- read paths ----------------------------------------------------

  @spec get_by_uri(URI.t() | String.t()) :: decoded() | nil
  def get_by_uri(uri) do
    case Repo.get_by(__MODULE__, uri: uri_to_str(uri)) do
      nil -> nil
      row -> decode(row)
    end
  end

  @spec list_all() :: [decoded()]
  def list_all do
    Repo.all(from u in __MODULE__, order_by: u.uri)
    |> Enum.map(&decode/1)
  end

  # --- encoding helpers ---------------------------------------------

  defp encode_caps(caps) when is_list(caps) do
    caps
    |> Enum.map(&Esr.Capability.to_map/1)
    |> Jason.encode!()
  end

  defp decode(%__MODULE__{} = row) do
    %{
      id: row.id,
      uri: URI.parse(row.uri),
      password_hash: row.password_hash,
      caps: decode_caps(row.caps_json)
    }
  end

  defp decode_caps(nil), do: []
  defp decode_caps(""), do: []

  defp decode_caps(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, list} when is_list(list) ->
        Enum.map(list, &Esr.Capability.from_map/1)

      _ ->
        []
    end
  end

  defp uri_to_str(%URI{} = u), do: URI.to_string(u)
  defp uri_to_str(s) when is_binary(s), do: s
end
