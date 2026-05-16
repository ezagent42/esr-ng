defmodule EsrCore.Repo.Migrations.Phase3MessageRoutings do
  @moduledoc """
  Per spec review #P1-4: same Message envelope (identity invariant
  per Decision #40) may be persisted into multiple Session
  contexts when D8 reply targets multiple session_uris.

  Solution: keep `messages` as single source of truth per
  message_uri (PK unchanged from Phase 2). Add this `message_routings`
  join table to track which sessions a message landed in.

  `MessageStore.write/2` upserts messages (no-op on PK conflict) and
  always inserts a new row here. `recent_in_session/2` and
  `in_session_since/2` join via this table.
  """
  use Ecto.Migration

  def change do
    create table(:message_routings, primary_key: false) do
      add :message_uri, :string, null: false
      add :session_uri, :string, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    # Composite PK — same message can land in multiple sessions,
    # but the (msg, session) pair is unique.
    create unique_index(:message_routings, [:message_uri, :session_uri],
             name: :message_routings_pkey
           )

    create index(:message_routings, [:session_uri, :inserted_at])
  end
end
