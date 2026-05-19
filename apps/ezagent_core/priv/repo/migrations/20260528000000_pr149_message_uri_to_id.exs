defmodule EzagentCore.Repo.Migrations.Pr149MessageUriToId do
  @moduledoc """
  PR #149 (SPEC v2 §5.13) — Message has no URI.

  Renames `messages.uri` → `messages.id` and `messages.ref` → `messages.ref_id`.
  Also renames `message_routings.message_uri` → `message_routings.message_id`
  so the join column matches the new id name. Strips the legacy
  `message://` prefix from any existing row contents — clean-rebuild path
  is `mix ezagent.db.reset`; this UPDATE is a safety net for data that
  survives a migration-only path.
  """
  use Ecto.Migration

  def change do
    rename table(:messages), :uri, to: :id
    rename table(:messages), :ref, to: :ref_id
    rename table(:message_routings), :message_uri, to: :message_id

    # Strip the `message://` prefix from any pre-existing rows so the
    # column stores plain UUID strings going forward.
    execute "UPDATE messages SET id = REPLACE(id, 'message://', '')"

    execute "UPDATE messages SET ref_id = REPLACE(ref_id, 'message://', '') " <>
              "WHERE ref_id IS NOT NULL"

    execute "UPDATE message_routings SET message_id = REPLACE(message_id, 'message://', '')"
  end
end
