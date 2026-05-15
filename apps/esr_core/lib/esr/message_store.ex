defmodule Esr.MessageStore do
  @moduledoc """
  Persistent chat history per ARCHITECTURE §10.4 + Decision P2-D3.

  Single source of truth for Message stream — Session.Chat state only
  tracks ephemeral in-flight membership (members / online / last_seen /
  monitors); historical data lives here. On member rejoin,
  `in_session_since/2` derives the replay set; no duplicate pending
  queue is maintained (memory `feedback_converge_to_uri_list`).

  ## Phase 2 API surface

  - `write/2(message, session_uri)` — persist Message in a session
    context. Synchronous (Phase 2 messages are first-class; write
    failure means caller's send fails, no silent degrade per
    DECISIONS impl-time §write-failure)
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
  alias Esr.Message
  alias EsrCore.Repo

  @replay_cap 1000

  @doc """
  Persist a Message in the given session context.

  `session_uri` is set on the schema row (not in the Message struct's
  identity per Decision #40); caller passes it explicitly so the
  Message envelope stays immutable across forwards.

  Returns `{:ok, message}` on success or `{:error, changeset_or_term}`
  on failure (caller decides what to do; per impl-time policy, send
  should fail rather than continue with partial state).
  """
  @spec write(Message.t(), URI.t()) :: {:ok, Message.t()} | {:error, term()}
  def write(%Message{} = msg, %URI{} = session_uri) do
    msg
    |> Map.put(:session_uri, session_uri)
    |> Repo.insert()
  end

  @doc """
  Messages in `session_uri` strictly after `since` (timestamp comparison).
  Ascending order. Used for rejoin replay.

  Bounded to `@replay_cap` rows (1000) per DECISIONS P2-D3 failure mode
  (4). Older messages remain in the table but won't be replayed all at
  once on a long-offline member's rejoin. Phase 3 will add
  pagination / explicit catch-up controls.
  """
  @spec in_session_since(URI.t(), DateTime.t()) :: [Message.t()]
  def in_session_since(%URI{} = session_uri, %DateTime{} = since) do
    from(m in Message,
      where: m.session_uri == ^session_uri and m.inserted_at > ^since,
      order_by: [asc: m.inserted_at],
      limit: @replay_cap
    )
    |> Repo.all()
  end

  @doc """
  N most-recent messages in `session_uri`, descending. Used by LV
  /admin mount to populate the chat stream with history.

  Returns at most `limit` rows; caller should reverse if it wants
  ascending order for display.
  """
  @spec recent_in_session(URI.t(), pos_integer()) :: [Message.t()]
  def recent_in_session(%URI{} = session_uri, limit) when is_integer(limit) and limit > 0 do
    from(m in Message,
      where: m.session_uri == ^session_uri,
      order_by: [desc: m.inserted_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Single Message lookup by URI. Returns `{:ok, message}` or `:error`.

  Used for `ref` chain following — if `msg.ref == "message://X"` and
  a consumer wants the original referenced message, this is the lookup.
  """
  @spec by_uri(String.t()) :: {:ok, Message.t()} | :error
  def by_uri(message_uri) when is_binary(message_uri) do
    case Repo.get(Message, message_uri) do
      nil -> :error
      %Message{} = m -> {:ok, m}
    end
  end
end
