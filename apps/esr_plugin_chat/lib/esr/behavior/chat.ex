defmodule Esr.Behavior.Chat do
  @moduledoc """
  Chat Behavior — Decision P2-D2 K-path: 4 actions, registered per-Kind
  subset to realize Decision #61 "ESR is router not req/resp app".

  ## Action / Kind matrix

      | action    | registered on Kind(s)                  | mode  |
      |-----------|----------------------------------------|-------|
      | :send     | Esr.Entity.Session                     | cast  |
      | :join     | Esr.Entity.Session                     | call  |
      | :leave    | Esr.Entity.Session                     | cast  |
      | :receive  | Esr.Entity.User, Esr.Entity.Agent      | cast  |

  Session-side actions (`:send / :join / :leave`) mutate the Session's
  `:chat` slice (`members` map / `monitors` ref→URI / `last_seen` URI→DateTime).
  When `:send` is invoked, recipients are derived from `msg.mentions` (or
  all `members` if mentions is empty), excluding the sender, and each
  receives a `chat/receive` dispatch on its own Kind. The Session also
  broadcasts to `esr:session:<self_uri>:events` so the LV chat stream
  picks up the message.

  ## Receive branching

  `:receive` switches on `ctx.kind_module`:
  - `Esr.Entity.User` — broadcast to `esr:user:<self_uri>:events`. LV
    subscribes for admin inbox / mention notifications.
  - `Esr.Entity.Agent` — 2c-step 1 wires bridge push (`agent_uri →
    bridge_id` map lives on `Esr.Bridge.V1Prototype.Server`). For 2b,
    the Agent branch returns `{:ok, slice}` (no-op) because no Agent
    is spawned at boot yet (DynamicSupervisor stays empty until a
    bridge announces).

  ## Offline state machine (P2-D3 failure modes)

  When a member joins, Session `Process.monitor`s the member's Kind pid.
  On `:DOWN`, `handle_kind_message/3` flips that member's `online` flag
  to false and records `last_seen = now` (no member removal). On rejoin
  (`:join` for an already-known member), the Session uses
  `Esr.MessageStore.in_session_since/2(self_uri, last_seen)` to replay
  missed messages — bounded by the @replay_cap in MessageStore (1000)
  per DECISIONS failure mode (4).

  ## Why ctx.self_uri and ctx.kind_module

  Both injected by `Esr.Kind.Runtime` immediately before invoke (single
  point of contact, plugins never plumb manually). Session uses
  `ctx.self_uri` to scope MessageStore writes and PubSub topics;
  receivers branch on `ctx.kind_module` to pick the delivery shape
  (broadcast vs bridge push).
  """

  @behaviour Esr.Behavior

  alias Esr.{Invocation, KindRegistry, Message, MessageStore}

  @impl Esr.Behavior
  def actions, do: [:send, :receive, :join, :leave]

  @impl Esr.Behavior
  def state_slice, do: :chat

  @impl Esr.Behavior
  def init_slice(_args) do
    # Slice shape is the union across Kinds — Session uses all three
    # maps; User/Agent's :receive doesn't read or write the slice but
    # leaving the keys here means a `Map.get` on any Kind returns the
    # consistent shape (defensive over the BehaviorRegistry per-Kind
    # subset model where User/Agent don't list Chat in `behaviors/0`
    # and so don't init this slice anyway — `Kind.Runtime` defaults
    # missing slices to `%{}`, which the Session-only fields tolerate).
    %{
      # %{URI => %{online: bool}}
      members: %{},
      # %{ref => URI} — Process.monitor refs
      monitors: %{},
      # %{URI => DateTime} — when last seen offline (only present for offline)
      last_seen: %{}
    }
  end

  # --- :send -------------------------------------------------------------

  @impl Esr.Behavior
  def invoke(:send, slice, %{message: %Message{} = msg}, ctx) do
    session_uri = ctx.self_uri

    # 1. Persist — write failure means send failure per DECISIONS
    # impl-time §write-failure; let-it-crash on Repo errors rather than
    # silently dropping the message.
    case MessageStore.write(msg, session_uri) do
      {:ok, _stored} ->
        # 2. Broadcast for in-session subscribers (LV chat stream).
        # Phase 3: include session_uri in payload so multi-session LV
        # subscribers can filter by current session.
        Phoenix.PubSub.broadcast(
          EsrCore.PubSub,
          session_events_topic(session_uri),
          {:chat_message, session_uri, msg}
        )

        # 3. Fan out routing decisions in two flavors:
        # (a) cross-session targets from Resolver → dispatch chat/send to
        #     that target session (it'll handle its own member fan-out)
        # (b) in-session members fan-out:
        #     - if Resolver returned any cross-session targets: still
        #       do in-session fan-out too (additive — message belongs
        #       to current session too)
        #     - if Resolver returned []: members-only (default)
        cross_session_targets = Esr.Routing.Resolver.resolve(msg, session_uri)
        in_session_members = Map.keys(slice.members)

        # Avoid recursion: don't dispatch to the current session as a
        # cross-session target (would loop forever).
        cross_filtered =
          Enum.reject(cross_session_targets, fn target ->
            URI.to_string(target) == URI.to_string(session_uri)
          end)

        for target_session <- cross_filtered do
          dispatch_cross_session(target_session, msg)
        end

        for member_uri <- in_session_members, member_uri != msg.sender do
          dispatch_receive(member_uri, msg, session_uri)
        end

        {:ok, slice, %{stored: true}}

      {:error, reason} ->
        {:error, {:message_store_write_failed, reason}}
    end
  end

  # --- :receive ----------------------------------------------------------

  def invoke(:receive, slice, %{message: %Message{} = msg}, ctx) do
    case ctx.kind_module do
      Esr.Entity.User ->
        Phoenix.PubSub.broadcast(
          EsrCore.PubSub,
          user_events_topic(ctx.self_uri),
          {:message_received, msg}
        )

        {:ok, slice}

      Esr.Entity.Agent ->
        # 2c-step 1 (+ Phase 3 P3-D8 source session in meta): look up
        # the bridge bound to this Agent's URI and push the body text
        # to claude via the SSE topic. Phase 3: include `session` in
        # meta so claude knows which session to fill in reply
        # `session_uris` field. ctx.caller is the Session that
        # dispatched this :receive (set in Chat.dispatch_receive).
        case Esr.Bridge.V1Prototype.Server.bridge_for_agent(ctx.self_uri) do
          {:ok, bridge_id} ->
            source_session =
              case Map.get(ctx, :caller) do
                %URI{} = u -> URI.to_string(u)
                s when is_binary(s) -> s
                _ -> ""
              end

            Esr.Bridge.V1Prototype.Server.push_to_claude(
              bridge_id,
              body_text(msg.body),
              %{
                "sender" => URI.to_string(msg.sender),
                "message_uri" => msg.uri,
                "session" => source_session
              }
            )

          :error ->
            :ok
        end

        {:ok, slice}

      _other ->
        # Should not happen — :receive is only registered for User/Agent.
        {:error, {:receive_unsupported_for_kind, ctx.kind_module}}
    end
  end

  # --- :join -------------------------------------------------------------

  def invoke(:join, slice, %{member: %URI{} = member_uri}, ctx) do
    session_uri = ctx.self_uri

    case KindRegistry.lookup(member_uri) do
      {:ok, member_pid} ->
        ref = Process.monitor(member_pid)

        new_members = Map.put(slice.members, member_uri, %{online: true})
        new_monitors = Map.put(slice.monitors, ref, member_uri)

        # If this member has prior last_seen, replay missed messages.
        replay_messages_since(session_uri, member_uri, slice.last_seen)
        new_last_seen = Map.delete(slice.last_seen, member_uri)

        new_slice = %{
          slice
          | members: new_members,
            monitors: new_monitors,
            last_seen: new_last_seen
        }

        broadcast_membership(session_uri, {:member_joined, member_uri})

        {:ok, new_slice, %{members: Map.keys(new_members)}}

      :error ->
        {:error, {:member_not_registered, member_uri}}
    end
  end

  # --- :leave ------------------------------------------------------------

  def invoke(:leave, slice, %{member: %URI{} = member_uri}, ctx) do
    {ref_to_remove, new_monitors} = pop_monitor_ref(slice.monitors, member_uri)

    if ref_to_remove, do: Process.demonitor(ref_to_remove, [:flush])

    new_slice = %{
      slice
      | members: Map.delete(slice.members, member_uri),
        monitors: new_monitors,
        last_seen: Map.delete(slice.last_seen, member_uri)
    }

    broadcast_membership(ctx.self_uri, {:member_left, member_uri})

    {:ok, new_slice}
  end

  # --- Kind-message hook -------------------------------------------------

  @doc """
  `Esr.Kind.Server.handle_info/2` forwards all GenServer messages here.
  Phase 2 handles `:DOWN` from `Process.monitor`; everything else is
  `:ignore`-ed (return value tells the server "slice unchanged").

  On `:DOWN` for a known member ref: flip `online` → false, record
  `last_seen = now`. The monitor ref is removed from `monitors` (no
  point holding a dead ref) but the URI stays in `members` so rejoin
  recognizes it.
  """
  def handle_kind_message({:DOWN, ref, :process, _pid, _reason}, slice, ctx) do
    case Map.pop(slice.monitors, ref) do
      {nil, _} ->
        # Not one of our monitors (could be another Behavior's ref or
        # a stale ref after a leave).
        :ignore

      {member_uri, new_monitors} ->
        now = DateTime.utc_now()

        new_members =
          Map.update(slice.members, member_uri, %{online: false}, &Map.put(&1, :online, false))

        new_last_seen = Map.put(slice.last_seen, member_uri, now)

        new_slice = %{
          slice
          | monitors: new_monitors,
            members: new_members,
            last_seen: new_last_seen
        }

        broadcast_membership(ctx.self_uri, {:member_offline, member_uri, now})

        {:ok, new_slice}
    end
  end

  # Bridge → Agent reply path (Phase 3c-step 2/3, P3-D8 contract).
  #
  # When the controller's forward_reply_to_agent/4 lands on the Agent's
  # mailbox, this clause constructs ONE chat envelope (identity invariant
  # per Decision #40) and dispatches `chat/send` once per session_uri in
  # the target list. Same Message URI lands in multiple sessions via
  # MessageStore.write upsert + message_routings rows (per #P1-4 fix).
  #
  # ref consistency soft warn (P3-D8): if `ref` is provided, look up the
  # ref'd Message's session presence and check it overlaps with the
  # supplied session_uris. Mismatch emits telemetry + audit warn but
  # STILL routes per the explicit session_uris (trust claude's choice).
  def handle_kind_message(
        {:reply_received, session_uris, text, ref_str_or_nil},
        _slice,
        %{kind_module: Esr.Entity.Agent} = ctx
      )
      when is_list(session_uris) and is_binary(text) do
    agent_uri = ctx.self_uri

    # Construct envelope once (identity invariant). ref is string at
    # wire boundary; parse to %URI{} for the Message struct.
    ref_uri =
      case ref_str_or_nil do
        nil -> nil
        "" -> nil
        s when is_binary(s) -> URI.new!(s)
      end

    msg =
      Message.new(agent_uri, %{text: text, attachments: []},
        ref: ref_uri
      )

    # Soft consistency check: ref'd message should have been seen in at
    # least one of the target sessions. Mismatch = noisy emit, not block.
    maybe_emit_ref_mismatch(ref_str_or_nil, session_uris)

    # Dispatch chat/send per session_uri. Message envelope shared.
    # Phase 3d: agent's reply dispatch runs under admin caps for the
    # same reason as Session fan-out — the reply path is system-routed
    # from the bridge. Phase 4 will give Agents their own send caps.
    #
    # Phase 3d quality fix: if dispatch fails (e.g. claude filled
    # session_uris with a non-existent session), emit telemetry +
    # audit warn instead of silently dropping. Real-claude e2e
    # exposed this — early replies before the meta-session fix
    # targeted "session://admin" which didn't exist and disappeared
    # silently.
    for session_uri_str <- session_uris do
      target = URI.new!("#{session_uri_str}/behavior/chat/send")

      result =
        Invocation.dispatch(%Invocation{
          target: target,
          mode: :cast,
          args: %{message: msg},
          ctx: %{
            caller: agent_uri,
            caps: Esr.Entity.User.admin_caps(),
            reply: :ignore
          }
        })

      case result do
        :ok ->
          :ok

        {:ok, _} ->
          :ok

        {:error, reason} ->
          :telemetry.execute(
            [:esr, :chat, :reply_dispatch_failed],
            %{},
            %{
              agent: URI.to_string(agent_uri),
              target_session: session_uri_str,
              reason: reason,
              message_uri: msg.uri
            }
          )
      end
    end

    # Slice unchanged — Agent has no chat state of its own.
    :ignore
  end

  def handle_kind_message(_other_message, _slice, _ctx), do: :ignore

  defp maybe_emit_ref_mismatch(nil, _), do: :ok
  defp maybe_emit_ref_mismatch("", _), do: :ok

  defp maybe_emit_ref_mismatch(ref_str, session_uris) when is_binary(ref_str) do
    case Esr.MessageStore.by_uri(ref_str) do
      :error ->
        # Ref points to unknown message — still warn (claude may have
        # made up a ref or referenced a pruned message).
        :telemetry.execute(
          [:esr, :chat, :reply_session_mismatch],
          %{},
          %{ref: ref_str, target_sessions: session_uris, reason: :ref_not_found}
        )

      {:ok, _msg} ->
        # Compare against actual presence (via message_routings join).
        actual_sessions = Esr.MessageStore.sessions_for_message(ref_str)

        intersection = MapSet.intersection(MapSet.new(actual_sessions), MapSet.new(session_uris))

        if MapSet.size(intersection) == 0 do
          :telemetry.execute(
            [:esr, :chat, :reply_session_mismatch],
            %{},
            %{
              ref: ref_str,
              target_sessions: session_uris,
              ref_actual_sessions: actual_sessions,
              reason: :no_overlap
            }
          )
        end
    end

    :ok
  end

  # --- Interface schema --------------------------------------------------

  @impl Esr.Behavior
  def interface do
    %{
      send: %{
        args: %{message: message_schema()},
        returns: %{stored: :boolean},
        modes: [:cast]
      },
      receive: %{
        args: %{message: message_schema()},
        returns: %{},
        modes: [:cast]
      },
      join: %{
        args: %{member: :uri},
        returns: %{members: {:list, :uri}},
        # Allow both — admin User joins via :cast at boot (non-blocking);
        # admin or programmatic callers may :call to read members back.
        modes: [:call, :cast]
      },
      leave: %{
        args: %{member: :uri},
        returns: %{},
        modes: [:cast]
      }
    }
  end

  # --- Topic helpers (public — Esr.Kind.Server / LV subscribe via these) -

  @doc "PubSub topic for in-session events (chat stream feed)."
  @spec session_events_topic(URI.t() | String.t()) :: String.t()
  def session_events_topic(%URI{} = uri), do: session_events_topic(URI.to_string(uri))
  def session_events_topic(uri_str) when is_binary(uri_str), do: "esr:session:#{uri_str}:events"

  @doc "PubSub topic for a User's personal receive notifications."
  @spec user_events_topic(URI.t() | String.t()) :: String.t()
  def user_events_topic(%URI{} = uri), do: user_events_topic(URI.to_string(uri))
  def user_events_topic(uri_str) when is_binary(uri_str), do: "esr:user:#{uri_str}:events"

  # --- Internals ---------------------------------------------------------

  defp dispatch_cross_session(target_session_uri, %Message{} = msg) do
    # Recursively dispatch chat/send on the target session — that
    # session handles its own member fan-out + further routing rules.
    target = URI.new!("#{URI.to_string(target_session_uri)}/behavior/chat/send")

    Invocation.dispatch(%Invocation{
      target: target,
      mode: :cast,
      args: %{message: msg},
      ctx: %{
        caller: msg.sender,
        caps: Esr.Entity.User.admin_caps(),
        reply: :ignore
      }
    })
  end

  defp dispatch_receive(recipient_uri, %Message{} = msg, session_uri) do
    target = URI.new!("#{URI.to_string(recipient_uri)}/behavior/chat/receive")

    # Phase 3d: Session's fan-out to recipients runs under admin caps —
    # the Session is acting on behalf of the system-routed message.
    # Phase 4+ will refine to a dedicated "system-internal" cap when
    # multi-user authorization arrives.
    Invocation.dispatch(%Invocation{
      target: target,
      mode: :cast,
      args: %{message: msg},
      ctx: %{
        caller: session_uri,
        caps: Esr.Entity.User.admin_caps(),
        reply: :ignore
      }
    })
  end

  defp replay_messages_since(_session_uri, _member_uri, last_seen) when last_seen == %{}, do: :ok

  defp replay_messages_since(session_uri, member_uri, last_seen) do
    case Map.get(last_seen, member_uri) do
      nil ->
        :ok

      last_seen_at ->
        for msg <- MessageStore.in_session_since(session_uri, last_seen_at) do
          dispatch_receive(member_uri, msg, session_uri)
        end

        :ok
    end
  end

  defp broadcast_membership(session_uri, event) do
    Phoenix.PubSub.broadcast(
      EsrCore.PubSub,
      session_events_topic(session_uri),
      event
    )
  end

  defp pop_monitor_ref(monitors, member_uri) do
    Enum.reduce(monitors, {nil, %{}}, fn
      {ref, ^member_uri}, {nil, acc} -> {ref, acc}
      {ref, uri}, {found_ref, acc} -> {found_ref, Map.put(acc, ref, uri)}
    end)
  end

  # Body comes back from MessageStore.load with string keys (Ecto :map
  # column → JSON-decoded via ecto_sqlite3); freshly-constructed bodies
  # in-flight have atom keys. Accept either to be safe across the
  # dispatch boundary.
  defp body_text(%{text: t}) when is_binary(t), do: t
  defp body_text(%{"text" => t}) when is_binary(t), do: t
  defp body_text(_), do: ""

  defp message_schema do
    %{
      uri: :string,
      sender: :uri,
      mentions: {:list, :uri},
      body: :map,
      ref: {:option, :uri},
      inserted_at: :map
    }
  end
end
