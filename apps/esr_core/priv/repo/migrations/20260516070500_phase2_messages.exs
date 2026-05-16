defmodule EsrCore.Repo.Migrations.Phase2Messages do
  use Ecto.Migration

  def change do
    # Phase 2 F (Message stream) per ARCHITECTURE §10.4 + Decision #83.
    # Append-only — each Message is identity-immutable across forwards
    # (Decision #40), so this table is the single source of truth for
    # chat history. Session.Chat state slice does NOT duplicate this
    # (Decision P2-D3 / memory feedback_converge_to_uri_list).
    create table(:messages, primary_key: false) do
      add :uri, :string, primary_key: true
      add :session_uri, :string, null: false
      add :sender, :string, null: false
      # mentions: JSON array of URI strings (ecto_sqlite3 :map / :array
      # auto-encode via Jason).
      # mentions: stored as TEXT (JSON-encoded array of URI strings) by
      # ecto_sqlite3. The schema declares `{:array, Esr.Ecto.URI}`,
      # which ecto_sqlite3 transparently JSON-encodes / decodes.
      add :mentions, {:array, :string}, null: false, default: []
      # body: JSON map `%{text, attachments}`.
      add :body, :map, null: false
      add :ref, :string
      add :inserted_at, :utc_datetime_usec, null: false
    end

    # Per §10.4 + the recent_in_session / in_session_since queries
    # MessageStore exposes.
    create index(:messages, [:session_uri, :inserted_at])
    create index(:messages, [:sender])
  end
end
