defmodule Esr.MessageRouting do
  @moduledoc """
  Join table for "this Message landed in these Sessions" (Phase 3 fix
  for #P1-4 multi-session persist).

  Phase 2 `messages.uri` is PK + identity-invariant per Decision #40 —
  same envelope across forwards. Phase 3 D8 reply may target N
  sessions in one operation; can't write `messages` table N times
  with same URI. This join table stores per-session presence;
  `messages` stays single-row-per-uri.

  Schema:
    message_uri    :string  (FK to messages.uri)
    session_uri    :string
    inserted_at    :utc_datetime_usec
  PK: composite (message_uri, session_uri)

  `MessageStore.write/2` upserts messages + inserts here.
  `MessageStore.recent_in_session/2` + `in_session_since/2` JOIN this
  table to get session-scoped Messages.
  """

  use Ecto.Schema

  @primary_key false
  schema "message_routings" do
    field :message_uri, :string, primary_key: true
    field :session_uri, :string, primary_key: true
    field :inserted_at, :utc_datetime_usec
  end

  @type t :: %__MODULE__{
          message_uri: String.t(),
          session_uri: String.t(),
          inserted_at: DateTime.t() | nil
        }
end
