defmodule Esr.MessageStore do
  @moduledoc """
  Persistent chat history per ARCHITECTURE §10.4 + Decision P2-D3.

  Single source of truth for Message stream — Session.Chat state only
  tracks ephemeral in-flight membership (members / online / last_seen /
  monitors); historical data lives here. On member rejoin,
  `in_session_since/2` derives the replay set; no duplicate pending
  queue is maintained (memory `feedback_converge_to_uri_list`).

  ## Phase 3 multi-session persist (#P1-4 fix)

  Phase 2 wrote `messages` table with `session_uri` column directly.
  Phase 3 D8 (reply to multiple sessions) needs same `message_uri` to
  appear in multiple sessions, but `messages.uri` is PK (Decision #40
  identity invariant). Resolution:

  - `messages` table: still 1 row per `message_uri`. `session_uri`
    column kept (set on first write only) for Phase 2 backward compat;
    queries in Phase 3 use the join table instead.
  - `message_routings` table (new): one row per `(message_uri, session_uri)`
    — the canonical per-session presence record.
  - `write/2` upserts messages (on_conflict: :nothing) + always inserts
    a fresh message_routings row.
  - `recent_in_session/2` + `in_session_since/2`: JOIN message_routings → messages.

  ## API surface

  - `write/2(message, session_uri)` — persist Message in a session
    context. Synchronous (Phase 2 messages are first-class; write
    failure means caller's send fails, no silent degrade per
    DECISIONS impl-time §write-failure). Idempotent on (message_uri,
    session_uri) pair via upsert + unique index.
  - `in_session_since/2(session_uri, since)` — messages in this
    session strictly after `since`. Ascending order. Used by
    `Session.Chat.invoke(:join, ...)` on rejoin to replay. Bounded
    via SQL `LIMIT 1000` per DECISIONS P2-D3 failure mode (4)
  - `recent_in_session/2(session_uri, limit)` — N most recent
    messages, descending. LV /admin mount uses this to render history
  - `by_uri/1(message_uri)` — single Message lookup for `ref` chain
    following / debugging

  All functions wrap `EsrCore.Repo` calls. Custom Ecto.URI type
  handles URI struct ↔ string at column boundary.
  """

  import Ecto.Query
  alias Esr.{Message, MessageRouting}
  alias EsrCore.Repo

  @replay_cap 1000

  @doc """
  Persist a Message in the given session context.

  Phase 3:
  - First-time write: insert `messages` row (with messages.session_uri
    set to this session) + insert `message_routings` row
  - Subsequent writes of same `message_uri` to a different session:
    upsert messages = noop (PK conflict on `:nothing`) + add
    `message_routings` row (different session_uri makes composite PK
    unique)

  Returns `{:ok, message}` on success or `{:error, _}` on failure.
  """
  @spec write(Message.t(), URI.t()) :: {:ok, Message.t()} | {:error, term()}
  def write(%Message{} = msg, %URI{} = session_uri) do
    msg_with_session = Map.put(msg, :session_uri, session_uri)
    now = msg.inserted_at || DateTime.utc_now()

    # Two-step write: messages (upsert) + message_routings (insert).
    # Wrapped in a transaction so we don't end up with messages row
    # but missing routing, or vice versa.
    Repo.transaction(fn ->
      case Repo.insert(msg_with_session, on_conflict: :nothing, conflict_target: :uri) do
        {:ok, _} ->
          routing = %MessageRouting{
            message_uri: msg.uri,
            session_uri: URI.to_string(session_uri),
            inserted_at: now
          }

          case Repo.insert(routing,
                 on_conflict: :nothing,
                 conflict_target: [:message_uri, :session_uri]
               ) do
            {:ok, _} -> msg_with_session
            {:error, reason} -> Repo.rollback(reason)
          end

        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Messages in `session_uri` strictly after `since` (timestamp comparison).
  Ascending order. Used for rejoin replay.

  JOINs message_routings → messages. Bounded to `@replay_cap` rows.
  """
  @spec in_session_since(URI.t(), DateTime.t()) :: [Message.t()]
  def in_session_since(%URI{} = session_uri, %DateTime{} = since) do
    session_str = URI.to_string(session_uri)

    from(m in Message,
      join: r in MessageRouting,
      on: r.message_uri == m.uri,
      where: r.session_uri == ^session_str and r.inserted_at > ^since,
      order_by: [asc: r.inserted_at],
      limit: @replay_cap
    )
    |> Repo.all()
  end

  @doc """
  N most-recent messages in `session_uri`, descending.

  JOINs message_routings → messages. Returns at most `limit`.
  """
  @spec recent_in_session(URI.t(), pos_integer()) :: [Message.t()]
  def recent_in_session(%URI{} = session_uri, limit) when is_integer(limit) and limit > 0 do
    session_str = URI.to_string(session_uri)

    from(m in Message,
      join: r in MessageRouting,
      on: r.message_uri == m.uri,
      where: r.session_uri == ^session_str,
      order_by: [desc: r.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Single Message lookup by URI. Returns `{:ok, message}` or `:error`.

  Used for `ref` chain following — if `msg.ref == "message://X"` and
  a consumer wants the original referenced message, this is the lookup.
  Returns the message with its **first-written** session_uri (Phase 2
  semantics) — for Phase 3 multi-session presence, query
  `message_routings` directly.
  """
  @spec by_uri(String.t()) :: {:ok, Message.t()} | :error
  def by_uri(message_uri) when is_binary(message_uri) do
    case Repo.get(Message, message_uri) do
      nil -> :error
      %Message{} = m -> {:ok, m}
    end
  end

  @doc """
  List all session URIs this message has been routed into.

  Phase 3 multi-session helper — for D8 ref/session_uris consistency
  check in `Esr.Behavior.Chat.handle_kind_message/3`.
  """
  @spec sessions_for_message(String.t()) :: [String.t()]
  def sessions_for_message(message_uri) when is_binary(message_uri) do
    from(r in MessageRouting,
      where: r.message_uri == ^message_uri,
      select: r.session_uri
    )
    |> Repo.all()
  end
end
