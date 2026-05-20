defmodule EzagentCore.Repo.Migrations.Pr142EntityTokens do
  @moduledoc """
  PR #142 SPEC v2 §5.12 — entity-agnostic bearer tokens.

  Replaces the User-table-only `cli_token` field with a separate
  `entity_tokens` table that can mint tokens for any Entity URI
  (`entity://user/default/X` or `entity://agent/default/Y_Z`).

  Per `entity-agnostic-architecture-reflection.md` §4 S-2 the table
  carries:

  - `entity_uri` — full URI string of the principal
  - `token_hash` — bcrypt of the plain bearer string
  - `label` — operator-readable name
  - `created_at` / `expires_at` / `last_used_at`

  Per SPEC §5.11 there is no back-compat migration of existing
  `users.cli_token` rows — clean rebuild via `mix ezagent.db.reset`
  is the cutover. The `users.cli_token` column is dropped here.
  """

  use Ecto.Migration

  def up do
    create table(:entity_tokens) do
      add :entity_uri, :string, null: false
      add :token_hash, :string, null: false
      add :label, :string
      add :expires_at, :utc_datetime_usec
      add :last_used_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:entity_tokens, [:entity_uri])

    # Drop the legacy User-only cli_token column. SQLite uses a 12-step
    # rebuild under the hood — Ecto's drop_index + remove handles it.
    drop_if_exists index(:users, [:cli_token], name: :users_cli_token_index)

    alter table(:users) do
      remove :cli_token
    end
  end

  def down do
    alter table(:users) do
      add :cli_token, :string
    end

    create unique_index(:users, [:cli_token], name: :users_cli_token_index)

    drop table(:entity_tokens)
  end
end
