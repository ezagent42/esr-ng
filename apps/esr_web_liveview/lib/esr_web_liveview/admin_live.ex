defmodule EsrWebLiveview.AdminLive do
  @moduledoc """
  /admin LiveView — coordinator shell.

  Phase 4a split (per Phase 4 D2): render fragments live in stateless
  Phoenix.Component modules under `EsrWebLiveview.Admin.*`. This module
  keeps:

  - mount + state assigns + stream setup
  - all handle_info subscriptions (audit / bridge / member / chat_message)
  - all handle_event handlers (echo / chat_compose / switch_session /
    create_session / add_agent_to_session / manual_dispatch)
  - a thin render/1 that composes the 4 components

  Sub-components (see `apps/esr_web_liveview/lib/esr_web_liveview/admin/`):

  - `EsrWebLiveview.Admin.SessionsSidebar` — left: sessions + new + floating
  - `EsrWebLiveview.Admin.ChatWindow` — center: header + stream + compose
  - `EsrWebLiveview.Admin.MemberPanel` — right: members table
  - `EsrWebLiveview.Admin.DebugPanel` — below: cc-bridges + debug area

  Phase 4 D2 originally specced LiveComponent-per-surface. We landed on
  Phoenix.Component (stateless) because admin_live's state is tightly
  coupled (sessions choice drives chat + members + sidebar). Stateless
  components give the file-boundary split (the goal — let 4b/c/d add
  features in their own files, not as new sections in admin_live)
  without the `send_update` ceremony LiveComponent would force.
  Promote individual components to LiveComponent later if/when they
  earn their own state (likely candidate: Workspace member-picker in 4d).
  """

  use Phoenix.LiveView
  import Phoenix.Component

  import EsrWebLiveview.Admin.SessionsSidebar
  import EsrWebLiveview.Admin.ChatWindow
  import EsrWebLiveview.Admin.MemberPanel
  import EsrWebLiveview.Admin.DebugPanel

  @echo_target URI.parse("agent://echo/behavior/echo/say")
  @main_session_uri URI.new!("session://main")
  @message_limit 50

  @impl true
  def mount(_params, session, socket) do
    connected_bridges = list_bridges_safely()
    current_session_uri = @main_session_uri

    if connected?(socket) do
      Phoenix.PubSub.subscribe(EsrCore.PubSub, Esr.Audit.stream_topic())
      Phoenix.PubSub.subscribe(EsrCore.PubSub, bridge_topic_safely())
      # Phase 3b: subscribe to ALL known sessions so floating/member updates
      # land for any session (not just current). Per-session message filtering
      # is done in handle_info for {:chat_message, session_uri, msg}.
      for session_uri <- EsrPluginChat.list_sessions() do
        Phoenix.PubSub.subscribe(EsrCore.PubSub, session_events_topic(session_uri))
      end
    end

    # Phase 4-completion Spec 05: derive caller from session cookie set
    # by SessionController. Falls back to admin if no session (e.g. test
    # paths that bypass login).
    caller_uri =
      case Map.get(session || %{}, "current_user_uri") do
        nil -> Esr.Entity.User.admin_uri()
        uri_str -> URI.parse(uri_str)
      end

    caller_caps =
      if URI.to_string(caller_uri) == URI.to_string(Esr.Entity.User.admin_uri()) do
        Esr.Entity.User.admin_caps()
      else
        Esr.Identity.list_caps_for(caller_uri)
      end

    socket =
      socket
      |> stream(:invocations, load_recent_invocations(50), limit: 50)
      |> stream(:messages, load_session_messages(current_session_uri), limit: @message_limit)
      |> assign(:caller_uri, caller_uri)
      |> assign(:caller_caps, caller_caps)
      |> assign(:caller_uri_str, URI.to_string(caller_uri))
      |> assign(:flash_error, nil)
      |> assign(:connected_bridges, connected_bridges)
      |> assign(:current_session_uri, current_session_uri)
      |> assign(:sessions, EsrPluginChat.list_sessions())
      |> assign(:session_members, read_session_members(current_session_uri))
      |> assign(:agent_options, list_session_agent_uris(current_session_uri))
      |> assign(:floating_agents, list_floating_agents())
      |> assign(:form,
        to_form(%{"target" => "", "args" => "", "mode" => "call"}, as: "manual_dispatch")
      )
      |> assign(:compose_form, to_form(%{"text" => "", "agent_uri" => ""}, as: "chat"))
      |> assign(:new_session_form, to_form(%{"short_name" => ""}, as: "new_session"))

    {:ok, socket}
  end

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
     |> assign(:agent_options, list_session_agent_uris(socket.assigns.current_session_uri))
     |> assign(:floating_agents, list_floating_agents())}
  end

  def handle_info({:cc_disconnected, _bridge_id}, socket) do
    {:noreply,
     socket
     |> assign(:connected_bridges, list_bridges_safely())
     |> assign(:agent_options, list_session_agent_uris(socket.assigns.current_session_uri))
     |> assign(:floating_agents, list_floating_agents())}
  end

  def handle_info({:member_joined, _uri}, socket),
    do:
      {:noreply,
       socket
       |> assign(:session_members, read_session_members(socket.assigns.current_session_uri))
       |> assign(:agent_options, list_session_agent_uris(socket.assigns.current_session_uri))
       |> assign(:floating_agents, list_floating_agents())}

  def handle_info({:member_left, _uri}, socket),
    do:
      {:noreply,
       socket
       |> assign(:session_members, read_session_members(socket.assigns.current_session_uri))
       |> assign(:agent_options, list_session_agent_uris(socket.assigns.current_session_uri))
       |> assign(:floating_agents, list_floating_agents())}

  def handle_info({:member_offline, _uri, _at}, socket),
    do:
      {:noreply,
       assign(socket, :session_members, read_session_members(socket.assigns.current_session_uri))}

  # Phase 3: chat_message carries the source session_uri; filter to
  # current_session_uri before inserting to the stream.
  def handle_info({:chat_message, source_session_uri, %Esr.Message{} = msg}, socket) do
    if URI.to_string(source_session_uri) == URI.to_string(socket.assigns.current_session_uri) do
      {:noreply, stream_insert(socket, :messages, message_to_row(msg), at: -1)}
    else
      {:noreply, socket}
    end
  end

  # Phase 2 backward-compat (in case any code still emits the old shape)
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
      ctx: ctx(socket)
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

    msg =
      Esr.Message.new(socket.assigns.caller_uri, %{text: text, attachments: []},
        mentions: mentions
      )

    target = URI.new!("#{URI.to_string(socket.assigns.current_session_uri)}/behavior/chat/send")

    inv = %Esr.Invocation{
      target: target,
      mode: :cast,
      args: %{message: msg},
      ctx: ctx(socket)
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
        {:noreply, assign(socket, :flash_error, friendly_error("Send", reason))}
    end
  end

  def handle_event("chat_compose", _params, socket) do
    {:noreply, assign(socket, :flash_error, "Message text is required.")}
  end

  # Phase 4-completion Spec 05 §A.2.4 — friendly flash for cap-deny.
  defp friendly_error(_action, :unauthorized) do
    "You don't have permission for this action. Contact admin for cap grant."
  end

  defp friendly_error(action, reason), do: "#{action} failed: #{inspect(reason)}"

  def handle_event("switch_session", %{"session_uri" => session_uri_str}, socket) do
    case URI.new(session_uri_str) do
      {:ok, new_uri} ->
        {:noreply,
         socket
         |> assign(:current_session_uri, new_uri)
         |> assign(:session_members, read_session_members(new_uri))
         |> assign(:agent_options, list_session_agent_uris(new_uri))
         |> stream(:messages, load_session_messages(new_uri), reset: true, limit: @message_limit)}

      _ ->
        {:noreply, assign(socket, :flash_error, "Bad session URI: #{session_uri_str}")}
    end
  end

  def handle_event("create_session", %{"new_session" => %{"short_name" => name}}, socket)
      when is_binary(name) and name != "" do
    case EsrPluginChat.create_session(String.trim(name), Esr.Entity.User.admin_uri()) do
      {:ok, session_uri} ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(EsrCore.PubSub, session_events_topic(session_uri))
        end

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
      )
      when session_uri_str != "" do
    with {:ok, agent_uri} <- URI.new(agent_uri_str),
         {:ok, session_uri} <- URI.new(session_uri_str) do
      target = URI.new!("#{URI.to_string(session_uri)}/behavior/chat/join")

      _ =
        Esr.Invocation.dispatch(%Esr.Invocation{
          target: target,
          mode: :cast,
          args: %{member: agent_uri},
          ctx: ctx(socket)
        })

      # member_joined broadcast will refresh assigns
      {:noreply, assign(socket, :flash_error, nil)}
    else
      _ -> {:noreply, assign(socket, :flash_error, "Bad URI for add-to-session")}
    end
  end

  # phx-change fires for every form update; ignore empty selection.
  def handle_event("add_agent_to_session", _params, socket), do: {:noreply, socket}

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
        ctx: ctx(socket)
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
          <a href="/admin/workspaces" style="margin-left: 16px; color: #0969da;">Workspaces →</a>
          <a href="/admin/routing" style="margin-left: 16px; color: #0969da;">Routing →</a>
          <a href="/admin/users" style="margin-left: 16px; color: #0969da;">Users →</a>
        </p>
      </header>

      <section id="layout" style="margin-top: 24px; display: grid; grid-template-columns: 200px 1fr 240px; gap: 16px;">
        <.sessions_sidebar
          sessions={@sessions}
          current_session_uri={@current_session_uri}
          floating_agents={@floating_agents}
          new_session_form={@new_session_form}
        />

        <.chat_window
          current_session_uri={@current_session_uri}
          messages_stream={@streams.messages}
          agent_options={@agent_options}
          compose_form={@compose_form}
          flash_error={@flash_error}
        />

        <.member_panel members={@session_members} />
      </section>

      <.debug_panel
        connected_bridges={@connected_bridges}
        form={@form}
        invocations_stream={@streams.invocations}
      />
    </div>
    """
  end

  # --- Helpers ----------------------------------------------------------

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

  # @ agent dropdown should only offer agents that can actually receive
  # in the current session — i.e. members of @current_session_uri.
  # Showing all KindRegistry agents (including floating) confused operators
  # because @-mentioning a floating agent silently drops (Phase 3 P3-D9).
  defp list_session_agent_uris(%URI{} = session_uri) do
    read_session_members(session_uri)
    |> Enum.map(& &1.uri)
    |> Enum.filter(&String.starts_with?(&1, "agent://"))
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

  defp ctx(socket) do
    %{
      caller: socket.assigns.caller_uri,
      caps: socket.assigns.caller_caps,
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

  # Phase 3d: :stub_grant gone. Real cap path emits :granted / :denied.
  defp authz_label([:esr, :authz, :granted]), do: "granted"
  defp authz_label([:esr, :authz, :denied]), do: "denied"
  defp authz_label([:esr, :invoke, :stop]), do: "granted"
  defp authz_label([:esr, :invoke, :error]), do: "—"
  defp authz_label(_), do: "—"

  defp result_label([:esr, :authz, :granted], _meta), do: "granted"
  defp result_label([:esr, :authz, :denied], %{caller: c}), do: "denied (caller=#{c})"
  defp result_label([:esr, :authz, :denied], _meta), do: "denied"
  defp result_label([:esr, :invoke, :stop], _meta), do: "ok"

  defp result_label([:esr, :invoke, :error], %{reason: :unauthorized}),
    do: "denied"

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
end
