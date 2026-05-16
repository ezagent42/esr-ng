defmodule EsrWebLiveview.AdminLive do
  @moduledoc """
  /admin LiveView — Phase 2 chat-window UI.

  Main view (top to bottom):

  1. **Session header** — `session://main` with members sidebar inline
     (URI / online status / last_seen).
  2. **Chat stream** — `Phoenix.LiveView.stream(:messages, limit: 50)`,
     mounted with `Esr.MessageStore.recent_in_session/2` and live-updated
     from `chat_message` broadcasts on `session:events`. Every row uses
     the same template — admin / agent sender differ only in subtle
     background colour. Phase 2 visual invariant: admin and agent rows
     are IDENTICAL DOM shape (no separate "from claude" panel).
  3. **Compose** — agent dropdown (live from KindRegistry scheme:agent
     entries) + text input + Send. Dispatches `session://main/behavior/chat/send`
     with `mentions: [selected agent]` (or `[]` for room broadcast).

  Debug area (below the main chat), `<details>` collapsible:
  - Phase 1 Echo button
  - Phase 1 Manual Dispatch form
  - Audit Log stream (`Phoenix.LiveView.stream(:invocations, limit: 50)`)

  Phase 1 forms moved to Debug — they're still useful for plumbing
  verification but should not occupy the main view (Phase 2 is
  Allen-chats-with-claude territory).

  ## Removed from Phase 1

  - `bridge_messages` assign + `:to_claude` / `:from_claude` rendering
  - "Send to Claude (via channel)" form (replaced by chat compose)
  - `channel_push` event handler (`push_to_claude` now happens inside
    `Esr.Behavior.Chat` `:receive` for Agent Kind)
  - `claude_reply` handle_info (replies now arrive via `chat_message`
    broadcast, having walked the full Chat router path)
  """

  use Phoenix.LiveView
  import Phoenix.Component

  @echo_target URI.parse("agent://echo/behavior/echo/say")
  @main_session_uri URI.new!("session://main")
  @message_limit 50

  @impl true
  def mount(_params, _session, socket) do
    connected_bridges = list_bridges_safely()
    current_session_uri = @main_session_uri

    if connected?(socket) do
      Phoenix.PubSub.subscribe(EsrCore.PubSub, Esr.Audit.stream_topic())
      Phoenix.PubSub.subscribe(EsrCore.PubSub, bridge_topic_safely())
      Phoenix.PubSub.subscribe(EsrCore.PubSub, session_events_topic(current_session_uri))
    end

    socket =
      socket
      |> stream(:invocations, load_recent_invocations(50), limit: 50)
      |> stream(:messages, load_session_messages(current_session_uri), limit: @message_limit)
      |> assign(:caller_uri_str, URI.to_string(Esr.Entity.User.admin_uri()))
      |> assign(:flash_error, nil)
      |> assign(:connected_bridges, connected_bridges)
      |> assign(:current_session_uri, current_session_uri)
      |> assign(:sessions, EsrPluginChat.list_sessions())
      |> assign(:session_members, read_session_members(current_session_uri))
      |> assign(:agent_options, list_agent_uris())
      |> assign(:floating_agents, list_floating_agents())
      |> assign(:form,
        to_form(%{"target" => "", "args" => "", "mode" => "call"}, as: "manual_dispatch")
      )
      |> assign(:compose_form, to_form(%{"text" => "", "agent_uri" => ""}, as: "chat"))
      |> assign(:new_session_form, to_form(%{"short_name" => ""}, as: "new_session"))

    {:ok, socket}
  end

  defp session_events_topic(%URI{} = uri) do
    Esr.Behavior.Chat.session_events_topic(uri)
  end

  defp load_session_messages(%URI{} = session_uri) do
    session_uri
    |> Esr.MessageStore.recent_in_session(@message_limit)
    |> Enum.reverse()
    |> Enum.map(&message_to_row/1)
  end

  defp read_session_members(%URI{} = session_uri) do
    case Esr.KindRegistry.lookup(session_uri) do
      {:ok, pid} ->
        try do
          %{state: %{chat: slice}} = :sys.get_state(pid, 1_000)

          for {uri, %{online: online?}} <- slice.members do
            %{
              uri: URI.to_string(uri),
              online: online?,
              last_seen: Map.get(slice.last_seen, uri)
            }
          end
          |> Enum.sort_by(& &1.uri)
        catch
          _, _ -> []
        end

      :error ->
        []
    end
  end

  defp list_agent_uris do
    Esr.KindRegistry.list_all()
    |> Enum.filter(fn {uri_str, _pid} -> String.starts_with?(uri_str, "agent://") end)
    |> Enum.map(fn {uri_str, _pid} -> uri_str end)
    |> Enum.sort()
  end

  # Floating = agent in KindRegistry but not in any Session.chat.members.
  defp list_floating_agents do
    all_agents = list_agent_uris() |> MapSet.new()

    joined =
      EsrPluginChat.list_sessions()
      |> Enum.flat_map(fn session_uri ->
        read_session_members(session_uri)
        |> Enum.map(& &1.uri)
      end)
      |> MapSet.new()

    MapSet.difference(all_agents, joined)
    |> Enum.sort()
  end

  defp bridge_topic_safely do
    if Code.ensure_loaded?(Esr.Bridge.V1Prototype.Server) do
      Esr.Bridge.V1Prototype.Server.topic()
    else
      "esr:bridge_v1:unavailable"
    end
  end

  defp list_bridges_safely do
    if Code.ensure_loaded?(Esr.Bridge.V1Prototype.Server) do
      Esr.Bridge.V1Prototype.Server.list_connected()
    else
      []
    end
  end

  defp load_recent_invocations(n) do
    %{rows: rows} =
      EsrCore.Repo.query!(
        "SELECT target, action, authz, duration_us, inserted_at " <>
          "FROM invocations ORDER BY id DESC LIMIT ?",
        [n]
      )

    Enum.map(rows, fn [target, action, authz, duration_us, inserted_at] ->
      %{
        id: "hist-#{:erlang.unique_integer([:positive, :monotonic])}",
        target: target,
        action: action || "—",
        authz: authz,
        result: "ok",
        duration_us: duration_us,
        at: format_inserted_at(inserted_at)
      }
    end)
  end

  defp format_inserted_at(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt)
  defp format_inserted_at(s) when is_binary(s), do: s
  defp format_inserted_at(other), do: inspect(other)

  # Row template — admin / agent sender pick different bg colour but
  # the SHAPE is identical (Phase 2 invariant per VERIFICATION 2c gate).
  defp message_to_row(%Esr.Message{} = msg) do
    sender_str = URI.to_string(msg.sender)

    %{
      id: msg.uri,
      uri: msg.uri,
      sender: sender_str,
      sender_kind: sender_kind(sender_str),
      text: body_text(msg.body),
      at: msg.inserted_at
    }
  end

  defp sender_kind(uri_str) do
    cond do
      String.starts_with?(uri_str, "user://") -> :user
      String.starts_with?(uri_str, "agent://") -> :agent
      true -> :other
    end
  end

  defp body_text(%{text: t}) when is_binary(t), do: t
  defp body_text(%{"text" => t}) when is_binary(t), do: t
  defp body_text(_), do: ""

  # --- Stream / membership / audit handlers -----------------------------

  @impl true
  def handle_info({:audit_event, event}, socket) do
    row = event_to_row(event)
    {:noreply, stream_insert(socket, :invocations, row, at: 0)}
  end

  def handle_info({:cc_connected, _bridge_id, _entry}, socket) do
    {:noreply,
     socket
     |> assign(:connected_bridges, list_bridges_safely())
     |> assign(:agent_options, list_agent_uris())}
  end

  def handle_info({:cc_disconnected, _bridge_id}, socket) do
    {:noreply,
     socket
     |> assign(:connected_bridges, list_bridges_safely())
     |> assign(:agent_options, list_agent_uris())}
  end

  def handle_info({:member_joined, _uri}, socket),
    do:
      {:noreply,
       socket
       |> assign(:session_members, read_session_members(socket.assigns.current_session_uri))
       |> assign(:agent_options, list_agent_uris())
       |> assign(:floating_agents, list_floating_agents())}

  def handle_info({:member_left, _uri}, socket),
    do:
      {:noreply,
       socket
       |> assign(:session_members, read_session_members(socket.assigns.current_session_uri))
       |> assign(:agent_options, list_agent_uris())
       |> assign(:floating_agents, list_floating_agents())}

  def handle_info({:member_offline, _uri, _at}, socket),
    do:
      {:noreply,
       assign(socket, :session_members, read_session_members(socket.assigns.current_session_uri))}

  def handle_info({:chat_message, %Esr.Message{} = msg}, socket) do
    {:noreply, stream_insert(socket, :messages, message_to_row(msg), at: -1)}
  end

  # --- User actions -----------------------------------------------------

  @impl true
  def handle_event("echo_test", _params, socket) do
    inv = %Esr.Invocation{
      target: @echo_target,
      mode: :call,
      args: %{msg: "hello"},
      ctx: ctx()
    }

    case Esr.Invocation.dispatch(inv) do
      {:ok, _result} ->
        {:noreply, assign(socket, :flash_error, nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :flash_error, "Echo failed: #{inspect(reason)}")}
    end
  end

  def handle_event("chat_compose", %{"chat" => %{"text" => text} = params}, socket)
      when is_binary(text) and text != "" do
    mentions =
      case Map.get(params, "agent_uri", "") do
        "" -> []
        uri_str -> [URI.new!(uri_str)]
      end

    admin_uri = Esr.Entity.User.admin_uri()
    msg = Esr.Message.new(admin_uri, %{text: text, attachments: []}, mentions: mentions)

    target = URI.new!("#{URI.to_string(socket.assigns.current_session_uri)}/behavior/chat/send")

    inv = %Esr.Invocation{
      target: target,
      mode: :cast,
      args: %{message: msg},
      ctx: ctx()
    }

    case Esr.Invocation.dispatch(inv) do
      :ok ->
        {:noreply,
         socket
         |> assign(:flash_error, nil)
         |> assign(:compose_form, to_form(%{"text" => "", "agent_uri" => ""}, as: "chat"))}

      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:flash_error, nil)
         |> assign(:compose_form, to_form(%{"text" => "", "agent_uri" => ""}, as: "chat"))}

      {:error, reason} ->
        {:noreply, assign(socket, :flash_error, "Send failed: #{inspect(reason)}")}
    end
  end

  def handle_event("chat_compose", _params, socket) do
    {:noreply, assign(socket, :flash_error, "Message text is required.")}
  end

  # --- Phase 3b: multi-session UX events --------------------------------

  def handle_event("switch_session", %{"session_uri" => session_uri_str}, socket) do
    case URI.new(session_uri_str) do
      {:ok, new_uri} ->
        # Re-subscribe: unsub old, sub new
        if connected?(socket) do
          Phoenix.PubSub.unsubscribe(
            EsrCore.PubSub,
            session_events_topic(socket.assigns.current_session_uri)
          )

          Phoenix.PubSub.subscribe(EsrCore.PubSub, session_events_topic(new_uri))
        end

        {:noreply,
         socket
         |> assign(:current_session_uri, new_uri)
         |> assign(:session_members, read_session_members(new_uri))
         |> stream(:messages, load_session_messages(new_uri), reset: true, limit: @message_limit)}

      _ ->
        {:noreply, assign(socket, :flash_error, "Bad session URI: #{session_uri_str}")}
    end
  end

  def handle_event("create_session", %{"new_session" => %{"short_name" => name}}, socket)
      when is_binary(name) and name != "" do
    case EsrPluginChat.create_session(String.trim(name), Esr.Entity.User.admin_uri()) do
      {:ok, _session_uri} ->
        {:noreply,
         socket
         |> assign(:sessions, EsrPluginChat.list_sessions())
         |> assign(:new_session_form, to_form(%{"short_name" => ""}, as: "new_session"))
         |> assign(:flash_error, nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :flash_error, "Create failed: #{inspect(reason)}")}
    end
  end

  def handle_event("create_session", _params, socket) do
    {:noreply, assign(socket, :flash_error, "Session name is required.")}
  end

  def handle_event(
        "add_agent_to_session",
        %{"agent_uri" => agent_uri_str, "session_uri" => session_uri_str},
        socket
      ) do
    with {:ok, agent_uri} <- URI.new(agent_uri_str),
         {:ok, session_uri} <- URI.new(session_uri_str) do
      target = URI.new!("#{URI.to_string(session_uri)}/behavior/chat/join")

      _ =
        Esr.Invocation.dispatch(%Esr.Invocation{
          target: target,
          mode: :cast,
          args: %{member: agent_uri},
          ctx: ctx()
        })

      # member_joined broadcast will refresh assigns
      {:noreply, assign(socket, :flash_error, nil)}
    else
      _ -> {:noreply, assign(socket, :flash_error, "Bad URI for add-to-session")}
    end
  end

  def handle_event(
        "manual_dispatch",
        %{"manual_dispatch" => %{"target" => target, "args" => args_json, "mode" => mode}},
        socket
      ) do
    with {:ok, target_uri} <- safe_uri(target),
         {:ok, args_map} <- safe_args(args_json),
         {:ok, mode_atom} <- safe_mode(mode) do
      inv = %Esr.Invocation{
        target: target_uri,
        mode: mode_atom,
        args: args_map,
        ctx: ctx()
      }

      case Esr.Invocation.dispatch(inv) do
        {:ok, _} -> {:noreply, assign(socket, :flash_error, nil)}
        :ok -> {:noreply, assign(socket, :flash_error, nil)}
        {:error, reason} -> {:noreply, assign(socket, :flash_error, "Dispatch failed: #{inspect(reason)}")}
      end
    else
      {:error, reason} ->
        {:noreply, assign(socket, :flash_error, reason)}
    end
  end

  # --- Render -----------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div style="max-width: 1200px; margin: 0 auto; padding: 24px; font-family: -apple-system, sans-serif;">
      <header>
        <h1 style="font-size: 22px; font-weight: 600;">Admin</h1>
        <p style="font-size: 13px; color: #666;">
          Caller: <code>{@caller_uri_str}</code>
        </p>
      </header>

      <section id="layout" style="margin-top: 24px; display: grid; grid-template-columns: 200px 1fr 240px; gap: 16px;">
        <aside id="sessions-sidebar" style="border-right: 1px solid #eaeef2; padding-right: 16px;">
          <h3 style="font-size: 14px; font-weight: 500; margin: 0 0 8px 0;">Sessions</h3>
          <ul id="sessions-list" style="list-style: none; padding: 0; margin: 0;">
            <li :for={uri <- @sessions} style="margin-bottom: 4px;">
              <button
                type="button"
                phx-click="switch_session"
                phx-value-session_uri={URI.to_string(uri)}
                style={session_button_style(URI.to_string(uri) == URI.to_string(@current_session_uri))}
              >
                {URI.to_string(uri)}
              </button>
            </li>
          </ul>

          <div id="new-session-form" style="margin-top: 12px; padding-top: 12px; border-top: 1px solid #eaeef2;">
            <.form for={@new_session_form} phx-submit="create_session">
              <label style="display: block; font-size: 11px; color: #57606a;" for="new_session_short_name">+ New session</label>
              <input
                type="text"
                name="new_session[short_name]"
                id="new_session_short_name"
                placeholder="architect-review"
                style="width: 100%; padding: 4px 6px; margin-top: 2px; font-size: 12px; border: 1px solid #d1d5da; border-radius: 4px;"
              />
              <button
                type="submit"
                style="margin-top: 4px; width: 100%; padding: 4px; font-size: 11px; background: white; color: #0969da; border: 1px solid #0969da; border-radius: 4px; cursor: pointer;"
              >
                Create
              </button>
            </.form>
          </div>

          <div id="floating-agents" :if={@floating_agents != []} style="margin-top: 16px; padding-top: 12px; border-top: 1px solid #eaeef2;">
            <h4 style="font-size: 11px; color: #57606a; font-weight: 500; margin: 0 0 6px 0;">Floating agents</h4>
            <div :for={agent <- @floating_agents} style="margin-bottom: 8px; padding: 4px; border: 1px dashed #d1d5da; border-radius: 4px; font-size: 11px;">
              <div style="font-family: monospace;">{agent}</div>
              <form phx-submit="add_agent_to_session" style="margin-top: 2px;">
                <input type="hidden" name="agent_uri" value={agent} />
                <select
                  name="session_uri"
                  style="width: 100%; font-size: 10px; padding: 2px;"
                >
                  <option value="">Add to session…</option>
                  <option :for={s <- @sessions} value={URI.to_string(s)}>{URI.to_string(s)}</option>
                </select>
              </form>
            </div>
          </div>
        </aside>

        <div>
          <h2 style="font-size: 16px; font-weight: 500; margin: 0 0 8px 0;">
            Session: <code>{URI.to_string(@current_session_uri)}</code>
          </h2>

          <div
            id="messages"
            phx-update="stream"
            style="height: 360px; overflow-y: auto; border: 1px solid #d1d5da; border-radius: 4px; padding: 12px; background: #fafbfc;"
          >
            <div :for={{dom_id, row} <- @streams.messages} id={dom_id} style={message_row_style(row.sender_kind)}>
              <div style="font-family: monospace; font-size: 11px; color: #57606a;">
                [{row.sender}] · {DateTime.to_iso8601(row.at)}
              </div>
              <div style="margin-top: 2px; white-space: pre-wrap;">{row.text}</div>
            </div>
          </div>

          <.form
            for={@compose_form}
            phx-submit="chat_compose"
            style="display: flex; gap: 8px; align-items: end; margin-top: 12px;"
          >
            <div style="flex: 0 0 240px;">
              <label style="display: block; font-size: 13px; font-weight: 500;" for="chat_agent_uri">@ agent</label>
              <select
                name="chat[agent_uri]"
                id="chat_agent_uri"
                style="width: 100%; padding: 6px 10px; border: 1px solid #d1d5da; border-radius: 4px;"
              >
                <option value="">— room (no mention) —</option>
                <option :for={uri <- @agent_options} value={uri}>{uri}</option>
              </select>
            </div>
            <div style="flex: 1 1 auto;">
              <label style="display: block; font-size: 13px; font-weight: 500;" for="chat_text">message</label>
              <input
                type="text"
                name="chat[text]"
                id="chat_text"
                value=""
                autocomplete="off"
                style="width: 100%; padding: 6px 10px; border: 1px solid #d1d5da; border-radius: 4px;"
              />
            </div>
            <button
              type="submit"
              id="chat-send-btn"
              style="padding: 8px 16px; background: #1f883d; color: white; border: none; border-radius: 4px; cursor: pointer;"
            >
              Send
            </button>
          </.form>
          <p :if={@flash_error} style="color: #cf222e; font-size: 13px; margin-top: 8px;">{@flash_error}</p>
        </div>

        <aside id="session-members" style="border-left: 1px solid #eaeef2; padding-left: 16px;">
          <h3 style="font-size: 14px; font-weight: 500; margin: 0 0 8px 0;">Members</h3>
          <p :if={@session_members == []} id="session-members-empty" style="font-size: 12px; color: #57606a;">
            (No members — Chat plugin failed to start?)
          </p>
          <table :if={@session_members != []} id="session-members-table" style="width: 100%; font-size: 12px; border-collapse: collapse;">
            <tbody>
              <tr :for={member <- @session_members} style="border-bottom: 1px solid #f0f0f0;">
                <td style="padding: 4px 0;">
                  <div style="font-family: monospace; font-size: 11px;">{member.uri}</div>
                  <div style={member_status_style(member.online)}>
                    {if member.online, do: "online", else: "offline"}
                    <span :if={member.last_seen} style="color: #999; font-weight: normal;">
                      · {DateTime.to_iso8601(member.last_seen)}
                    </span>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </aside>
      </section>

      <section id="cc-bridges" style="margin-top: 24px;">
        <h2 style="font-size: 16px; font-weight: 500; margin: 0 0 8px 0;">CC Bridges (v1 prototype)</h2>
        <p :if={@connected_bridges == []} id="bridge-empty" style="font-size: 13px; color: #57606a;">
          No connected bridges. Start one with <code>bash scripts/cc-bridge-attach.sh</code>.
        </p>
        <table :if={@connected_bridges != []} id="bridges-table" style="width: 100%; font-size: 13px; border-collapse: collapse;">
          <thead>
            <tr style="border-bottom: 1px solid #d1d5da;">
              <th style="text-align: left; padding: 4px 0;">bridge_id</th>
              <th style="text-align: left;">status</th>
              <th style="text-align: left;">connected_at</th>
              <th style="text-align: left;">client</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={{bridge_id, entry} <- @connected_bridges} style="border-bottom: 1px solid #eee;">
              <td style="font-family: monospace; padding: 4px 0;">{bridge_id}</td>
              <td style="color: #1f883d; font-weight: 600;">connected</td>
              <td style="color: #57606a;">{DateTime.to_iso8601(entry.connected_at)}</td>
              <td style="font-family: monospace; font-size: 11px;">{client_label(entry)}</td>
            </tr>
          </tbody>
        </table>
      </section>

      <section id="debug-area" style="margin-top: 32px;">
        <details>
          <summary style="font-size: 14px; font-weight: 500; cursor: pointer; padding: 8px 0;">
            Debug (Echo / Manual Dispatch / Audit Log)
          </summary>

          <div id="quick-actions" style="margin-top: 16px;">
            <h3 style="font-size: 14px; font-weight: 500; margin: 0 0 8px 0;">Quick Actions</h3>
            <button
              type="button"
              phx-click="echo_test"
              id="echo-test-btn"
              style="padding: 8px 16px; background: #0969da; color: white; border: none; border-radius: 4px; cursor: pointer;"
            >
              Echo 测试
            </button>
          </div>

          <div id="manual-dispatch" style="margin-top: 16px;">
            <h3 style="font-size: 14px; font-weight: 500; margin: 0 0 8px 0;">Manual Dispatch</h3>
            <.form for={@form} phx-submit="manual_dispatch">
              <div style="margin-bottom: 8px;">
                <label style="display: block; font-size: 13px; font-weight: 500;" for="manual_dispatch_target">target</label>
                <input
                  type="text"
                  name="manual_dispatch[target]"
                  id="manual_dispatch_target"
                  placeholder="agent://echo/behavior/echo/say"
                  style="width: 100%; padding: 6px 10px; border: 1px solid #d1d5da; border-radius: 4px;"
                />
              </div>
              <div style="margin-bottom: 8px;">
                <label style="display: block; font-size: 13px; font-weight: 500;" for="manual_dispatch_args">args (JSON)</label>
                <input
                  type="text"
                  name="manual_dispatch[args]"
                  id="manual_dispatch_args"
                  placeholder='{"msg": "hello"}'
                  style="width: 100%; padding: 6px 10px; border: 1px solid #d1d5da; border-radius: 4px;"
                />
              </div>
              <div style="margin-bottom: 8px;">
                <label style="display: block; font-size: 13px; font-weight: 500;" for="manual_dispatch_mode">mode</label>
                <select
                  name="manual_dispatch[mode]"
                  id="manual_dispatch_mode"
                  style="padding: 6px 10px; border: 1px solid #d1d5da; border-radius: 4px;"
                >
                  <option value="call">call</option>
                  <option value="cast">cast</option>
                </select>
              </div>
              <button
                type="submit"
                style="padding: 8px 16px; background: white; color: #0969da; border: 1px solid #0969da; border-radius: 4px; cursor: pointer;"
              >
                Dispatch
              </button>
            </.form>
          </div>

          <div id="audit-stream" style="margin-top: 16px;">
            <h3 style="font-size: 14px; font-weight: 500; margin: 0 0 8px 0;">Audit Log (last 50)</h3>
            <table style="width: 100%; font-size: 13px; border-collapse: collapse;">
              <thead>
                <tr style="border-bottom: 1px solid #d1d5da;">
                  <th style="text-align: left; padding: 6px 0;">target</th>
                  <th style="text-align: left;">action</th>
                  <th style="text-align: left;">authz</th>
                  <th style="text-align: left;">result</th>
                  <th style="text-align: left;">duration_us</th>
                  <th style="text-align: left;">at</th>
                </tr>
              </thead>
              <tbody id="invocations" phx-update="stream">
                <tr :for={{dom_id, row} <- @streams.invocations} id={dom_id} style="border-bottom: 1px solid #eee;">
                  <td style="padding: 4px 0; font-family: monospace; font-size: 11px;">{row.target}</td>
                  <td>{row.action}</td>
                  <td>{row.authz}</td>
                  <td style="font-family: monospace; font-size: 11px;">{row.result}</td>
                  <td>{row.duration_us}</td>
                  <td style="color: #666;">{row.at}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </details>
      </section>
    </div>
    """
  end

  # --- Helpers ----------------------------------------------------------

  defp ctx do
    %{
      caller: Esr.Entity.User.admin_uri(),
      caps: Esr.Entity.User.admin_caps(),
      reply: :ignore
    }
  end

  defp event_to_row(%{event: event, measurements: m, metadata: meta, at: at}) do
    %{
      id: "ev-#{:erlang.unique_integer([:positive, :monotonic])}",
      target: Map.get(meta, :target, "—"),
      action: stringify(Map.get(meta, :action)),
      authz: authz_label(event),
      result: result_label(event, meta),
      duration_us: Map.get(m, :duration_us, 0),
      at: DateTime.to_iso8601(at)
    }
  end

  defp client_label(%{info: %{claude_info: %{"name" => name, "version" => v}}}),
    do: "#{name} #{v}"

  defp client_label(%{info: %{claude_info: %{"name" => name}}}), do: name
  defp client_label(_), do: "—"

  defp authz_label([:esr, :invoke, :stop]), do: "stub_grant"
  defp authz_label([:esr, :invoke, :error]), do: "—"
  defp authz_label(_), do: "—"

  defp result_label([:esr, :invoke, :stop], _meta), do: "ok"
  defp result_label([:esr, :invoke, :error], %{reason: r}), do: "err: #{inspect(r)}"
  defp result_label(_, _), do: "—"

  defp stringify(nil), do: "—"
  defp stringify(a) when is_atom(a), do: Atom.to_string(a)
  defp stringify(s) when is_binary(s), do: s

  defp safe_uri(s) when is_binary(s) do
    case URI.new(s) do
      {:ok, %URI{scheme: nil}} -> {:error, "target must include a scheme (e.g. agent://...)"}
      {:ok, uri} -> {:ok, uri}
      {:error, _} -> {:error, "malformed URI"}
    end
  end

  defp safe_uri(_), do: {:error, "target missing"}

  defp safe_args(""), do: {:ok, %{}}

  defp safe_args(json) when is_binary(json) do
    case Jason.decode(json, keys: :atoms) do
      {:ok, m} when is_map(m) -> {:ok, m}
      {:ok, _} -> {:error, "args must be a JSON object"}
      {:error, _} -> {:error, "invalid JSON in args"}
    end
  end

  defp safe_args(_), do: {:ok, %{}}

  defp safe_mode("call"), do: {:ok, :call}
  defp safe_mode("cast"), do: {:ok, :cast}
  defp safe_mode(other), do: {:error, "unsupported mode: #{inspect(other)}"}

  defp member_status_style(true), do: "font-size: 11px; color: #1f883d; font-weight: 600;"
  defp member_status_style(false), do: "font-size: 11px; color: #999;"

  defp session_button_style(true) do
    "width: 100%; text-align: left; padding: 6px 8px; background: #0969da; color: white; border: none; border-radius: 4px; cursor: pointer; font-family: monospace; font-size: 11px;"
  end

  defp session_button_style(false) do
    "width: 100%; text-align: left; padding: 6px 8px; background: white; color: #0969da; border: 1px solid #d1d5da; border-radius: 4px; cursor: pointer; font-family: monospace; font-size: 11px;"
  end

  # Chat row backgrounds — admin浅蓝, agent浅绿. SAME DOM SHAPE — only
  # the wrapper bg colour differs. Phase 2 visual invariant.
  defp message_row_style(:user),
    do: "padding: 8px 10px; margin-bottom: 6px; background: #ddf4ff; border-radius: 4px;"

  defp message_row_style(:agent),
    do: "padding: 8px 10px; margin-bottom: 6px; background: #dafbe1; border-radius: 4px;"

  defp message_row_style(_),
    do: "padding: 8px 10px; margin-bottom: 6px; background: #f6f8fa; border-radius: 4px;"
end
