defmodule EzagentCore.Repo.Migrations.MagicLinkTokens do
  @moduledoc """
  Username & Auth M3 — single-use, short-TTL magic-link tokens.

  Separate from `entity_tokens` (which is bcrypt long-lived bearer
  auth) because the semantics differ: magic links are single-use,
  15-min TTL, and the raw token travels in a URL. `token_hash` is
  SHA-256 of the raw token (raw token is high-entropy random, so a
  fast hash is sufficient and lets us look it up by index).
  """
  use Ecto.Migration

  def change do
    create table(:magic_link_tokens) do
      add :email, :string, null: false
      add :token_hash, :binary, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :consumed_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:magic_link_tokens, [:token_hash])
    create index(:magic_link_tokens, [:email])
  end
end
