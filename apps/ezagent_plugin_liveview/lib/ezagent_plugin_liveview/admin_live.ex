defmodule EzagentPluginLiveview.AdminLive do
  @moduledoc """
  /sessions LiveView — Session Activity coordinator.

  ## Phase 8b — Session view-mode (replaces v1 three-column inline layout)

  Per `docs/superpowers/specs/2026-05-20-phase-8b-session-lv-redesign.zh_cn.md`:

  - Main Window hosts `EzagentPluginLiveview.Admin.SessionEditor`, a
    header (session selector + view-switcher + setting dropdown) /
    `:main_view` slot (the active `Ezagent.UI.SessionView` render) /
    composer (inline `@` autocomplete + file upload + send).
  - View-switcher options come from
    `Ezagent.UI.SessionViewRegistry.applicable_views(@current_session_uri)`.
    Plugins register views (conversation, pty, ...) in their own
    `Application.start/2`.
  - IDE Shell Right Sidebar still hosts `MemberPanel`. cc-agent rows
    get a 🖥️ button — click fires `switch_to_pty_for_agent`, the
    handler sets `current_view = :pty` + `active_pty_agent_uri`.
  - The Phase 4a `debug_panel` (Echo / Manual Dispatch / Audit) has
    moved to `/admin/logs` (ObservabilityLive). admin_live no longer
    renders it; the related handlers (`echo_test`, `manual_dispatch`)
    are gone from this module.

  ## Owned state (assigns)

  - `:current_session_uri` — which session is in view
  - `:current_view` — `:conversation` | `:pty` (default `:conversation`)
  - `:active_pty_agent_uri` — string, set when `current_view = :pty`
  - `:applicable_views` — derived from SessionViewRegistry on session change
  - `:session_members`, `:member_options`, `:floating_agents` — Members panel + composer
  - `:feishu_chat_ids` — for setting dropdown
  - `:debug_open` — Debug events panel toggle (setting dropdown)
  - `:compose_form`, `:new_session_form` — input + create
  """

  use Phoenix.LiveView
  import Phoenix.Component

  alias EzagentPluginLiveview.Admin.{SessionEditor, MemberPanel}
  alias EzagentPluginLiveview.Views.ConversationView
  alias EzagentDomainUi.IdeShell
  alias Ezagent.UI.SessionViewRegistry

  @main_session_uri URI.new!("session://main")
  @message_limit 50

  @impl true
  def mount(_params, _session, socket) do
    # Phase 8b — register the default ConversationView lazily here. The
    # liveview plugin is library-only (no Application module — adding
    # one in the umbrella triggered a DB-sandbox boot regression for the
    # rest of the LV test suite). Registration is idempotent so every
    # mount safely no-ops if another LV already registered.
    :ok = SessionViewRegistry.init()
    :ok = SessionViewRegistry.register(ConversationView)

    current_session_uri = @main_session_uri

    if connected?(socket) do
      Phoenix.PubSub.subscribe(EzagentCore.PubSub, Ezagent.Audit.stream_topic())
      Phoenix.PubSub.subscribe(EzagentCore.PubSub, bridge_topic_safely())
      Phoenix.PubSub.subscribe(EzagentCore.PubSub, Ezagent.CCEvents.topic())

      for session_uri <- EzagentDomainChat.list_sessions() do
        Phoenix.PubSub.subscribe(EzagentCore.PubSub, session_events_topic(session_uri))
      end
    end

    caller_uri = socket.assigns.current_entity_uri

    caller_caps =
      if URI.to_string(caller_uri) == URI.to_string(Ezagent.Entity.User.admin_uri()) do
        Ezagent.Entity.User.admin_caps()
      else
        Ezagent.Identity.list_caps_for(caller_uri)
      end

    initial_messages = load_session_messages(current_session_uri)

    socket =
      socket
      |> stream(:messages, initial_messages)
      |> assign(:oldest_cursor, oldest_cursor(initial_messages))
      # Phase 8c PR-B — empty-state flag for ConversationView. Tracks
      # whether any message has been rendered yet so the view can show a
      # dot-grid placeholder instead of a blank white panel.
      |> assign(:messages_empty?, initial_messages == [])
      |> assign(:caller_uri, caller_uri)
      |> assign(:caller_caps, caller_caps)
      |> assign(:caller_uri_str, URI.to_string(caller_uri))
      |> assign(:flash_error, nil)
      |> assign(:current_session_uri, current_session_uri)
      |> assign(:sessions, EzagentDomainChat.list_sessions())
      |> assign_session_context(current_session_uri)
      |> assign(:current_view, :conversation)
      |> assign(:active_pty_agent_uri, nil)
      |> assign(:cc_events, [])
      |> assign(:debug_open, false)
      |> assign(:compose_form, to_form(%{"text" => ""}, as: "chat"))
      |> assign(:new_session_form, to_form(%{"short_name" => ""}, as: "new_session"))
      |> allow_upload(:attachments,
        accept: :any,
        max_entries: 5,
        max_file_size: 10 * 1024 * 1024
      )

    {:ok, socket}
  end

  # --- Stream / membership / audit handlers -----------------------------

  @impl true
  def handle_info({:audit_event, _event}, socket) do
    # Audit stream moved to /admin/logs (ObservabilityLive). Drop here
    # so the subscription on Audit.stream_topic doesn't leak.
    {:noreply, socket}
  end

  def handle_info({:cc_event, event}, socket) do
    {:noreply, assign(socket, :cc_events, [event | socket.assigns.cc_events] |> Enum.take(20))}
  end

  def handle_info({:cc_connected, _bridge_id, _entry}, socket) do
    {:noreply, refresh_views_and_members(socket)}
  end

  def handle_info({:cc_disconnected, _bridge_id}, socket) do
    {:noreply, refresh_views_and_members(socket)}
  end

  def handle_info({:member_joined, _uri}, socket),
    do: {:noreply, refresh_views_and_members(socket)}

  def handle_info({:member_left, _uri}, socket),
    do: {:noreply, refresh_views_and_members(socket)}

  def handle_info({:member_offline, _uri, _at}, socket),
    do: {:noreply, assign_session_context(socket, socket.assigns.current_session_uri)}

  def handle_info({:chat_message, source_session_uri, %Ezagent.Message{} = msg}, socket) do
    if URI.to_string(source_session_uri) == URI.to_string(socket.assigns.current_session_uri) do
      {:noreply,
       socket
       |> assign(:messages_empty?, false)
       |> stream_insert(:messages, message_to_row(msg), at: -1)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:chat_message, %Ezagent.Message{} = msg}, socket) do
    {:noreply,
     socket
     |> assign(:messages_empty?, false)
     |> stream_insert(:messages, message_to_row(msg), at: -1)}
  end

  # --- User actions -----------------------------------------------------

  @impl true
  def handle_event("validate_compose", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :attachments, ref)}
  end

  def handle_event("chat_compose", %{"chat" => %{"text" => text}}, socket)
      when is_binary(text) do
    mentions = parse_mentions(text)

    File.mkdir_p!(Ezagent.Home.path("uploads"))

    attachments =
      consume_uploaded_entries(socket, :attachments, fn %{path: tmp_path}, entry ->
        uuid = Ecto.UUID.generate()
        safe_name = sanitize_filename(entry.client_name)
        stored_name = "#{uuid}-#{safe_name}"
        dest = Path.join(Ezagent.Home.path("uploads"), stored_name)
        File.cp!(tmp_path, dest)
        {:ok, URI.parse("resource://uploads/#{stored_name}")}
      end)

    if String.trim(text) == "" and attachments == [] do
      {:noreply,
       assign(socket, :flash_error, "Message text or at least one attachment is required.")}
    else
      send_chat_message(socket, text, attachments, mentions)
    end
  end

  def handle_event("chat_compose", _params, socket) do
    {:noreply, assign(socket, :flash_error, "Message text or at least one attachment is required.")}
  end

  def handle_event("switch_session", %{"session_uri" => session_uri_str}, socket) do
    case URI.new(session_uri_str) do
      {:ok, new_uri} ->
        new_messages = load_session_messages(new_uri)
        applicable = SessionViewRegistry.applicable_views(new_uri)

        new_view =
          cond do
            Enum.any?(applicable, &(&1.id == socket.assigns.current_view)) ->
              socket.assigns.current_view

            applicable != [] ->
              hd(applicable).id

            true ->
              :conversation
          end

        {:noreply,
         socket
         |> assign(:current_session_uri, new_uri)
         |> assign_session_context(new_uri)
         |> assign(:current_view, new_view)
         # Reset PTY agent binding — the new session may not have that
         # agent as a member.
         |> assign(:active_pty_agent_uri, nil)
         |> assign(:oldest_cursor, oldest_cursor(new_messages))
         |> assign(:messages_empty?, new_messages == [])
         |> stream(:messages, new_messages, reset: true)}

      _ ->
        {:noreply, assign(socket, :flash_error, "Bad session URI: #{session_uri_str}")}
    end
  end

  def handle_event("create_session", %{"new_session" => %{"short_name" => name}}, socket)
      when is_binary(name) and name != "" do
    case EzagentDomainChat.create_session(String.trim(name), Ezagent.Entity.User.admin_uri()) do
      {:ok, session_uri} ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(EzagentCore.PubSub, session_events_topic(session_uri))
        end

        {:noreply,
         socket
         |> assign(:sessions, EzagentDomainChat.list_sessions())
         |> assign(:new_session_form, to_form(%{"short_name" => ""}, as: "new_session"))
         |> assign(:flash_error, nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :flash_error, "Create failed: #{inspect(reason)}")}
    end
  end

  def handle_event("create_session", _params, socket) do
    {:noreply, assign(socket, :flash_error, "Session name is required.")}
  end

  # Phase 8b §3 stage c — view switcher (Chat / Terminal buttons in
  # SessionEditor header). `view` is the SessionView id atom encoded
  # as a string in the phx-value attribute; convert via
  # String.to_existing_atom to keep the atom table bounded.
  def handle_event("switch_view", %{"view" => view_str}, socket) do
    case safe_view_id(view_str) do
      {:ok, id} -> {:noreply, assign(socket, :current_view, id)}
      :error -> {:noreply, socket}
    end
  end

  # Phase 8b §3 stage g — clicking the 🖥️ button in MemberPanel
  # switches the main view to :pty and binds xterm to the chosen agent.
  def handle_event("switch_to_pty_for_agent", %{"agent" => agent_uri_str}, socket) do
    {:noreply,
     socket
     |> assign(:current_view, :pty)
     |> assign(:active_pty_agent_uri, agent_uri_str)}
  end

  # Phase 8b §1.6 — Debug events toggle in setting dropdown.
  def handle_event("toggle_debug_panel", _params, socket) do
    {:noreply, assign(socket, :debug_open, not socket.assigns.debug_open)}
  end

  # Phase 8b §1.6 — Feishu binding unbind action.
  def handle_event("unbind_feishu_chat", %{"chat_id" => chat_id}, socket) do
    _ =
      if Code.ensure_loaded?(EzagentPluginFeishu.SessionBinding) do
        EzagentPluginFeishu.SessionBinding.unbind(chat_id)
      end

    {:noreply, assign_session_context(socket, socket.assigns.current_session_uri)}
  end

  # PTY input dispatch — when PtyView is active, xterm pushes pty_input.
  def handle_event("pty_input", %{"bytes" => bytes}, socket) when is_binary(bytes) do
    case socket.assigns.active_pty_agent_uri do
      nil ->
        {:noreply, socket}

      agent_uri_str ->
        case URI.new(agent_uri_str) do
          {:ok, agent_uri} ->
            target = URI.parse(URI.to_string(agent_uri) <> "?action=pty.write")

            inv = %Ezagent.Invocation{
              target: target,
              mode: :cast,
              args: %{bytes: bytes},
              ctx: ctx(socket)
            }

            case Ezagent.Invocation.dispatch(inv) do
              :ok -> {:noreply, socket}
              {:ok, _} -> {:noreply, socket}
              {:error, :unauthorized} ->
                {:noreply,
                 assign(socket, :flash_error,
                   "Unauthorized — need agent.pty.write cap on this agent."
                 )}

              {:error, reason} ->
                {:noreply, assign(socket, :flash_error, "PTY input failed: #{inspect(reason)}")}
            end

          _ ->
            {:noreply, socket}
        end
    end
  end

  def handle_event("pty_resize", _params, socket), do: {:noreply, socket}

  # Phase 5 PR 5 — paginate history backwards.
  def handle_event("load_older_messages", _params, socket) do
    case socket.assigns.oldest_cursor do
      nil ->
        {:noreply, socket}

      %DateTime{} = cursor ->
        older =
          socket.assigns.current_session_uri
          |> Ezagent.MessageStore.older_than(cursor, @message_limit)
          |> Enum.reverse()
          |> Enum.map(&message_to_row/1)

        socket =
          Enum.reduce(older, socket, fn row, acc ->
            stream_insert(acc, :messages, row, at: 0)
          end)

        {:noreply, assign(socket, :oldest_cursor, oldest_cursor(older) || cursor)}
    end
  end

  # --- Render -----------------------------------------------------------

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign_new(:status, fn ->
        %{
          session_uri: assigns.current_session_uri,
          agents_alive: count_alive_agents(),
          bridges: count_connected_bridges(),
          debug_events: length(assigns.cc_events),
          version: ezagent_version()
        }
      end)
      |> assign_new(:view_render_fn, fn -> resolve_view_render(assigns) end)

    ~H"""
    <IdeShell.ide_shell
      current_entity_uri={@caller_uri_str}
      current_path="/sessions"
      status={@status}
    >
      <:main_window>
        <SessionEditor.session_editor
          current_session_uri={@current_session_uri}
          sessions={@sessions}
          applicable_views={@applicable_views}
          current_view={@current_view}
          new_session_form={@new_session_form}
          compose_form={@compose_form}
          member_options={@member_options}
          session_info={@session_info}
          feishu_chat_ids={@feishu_chat_ids}
          debug_open={@debug_open}
          uploads={@uploads}
          flash_error={@flash_error}
        >
          <:main_view>
            <.render_active_view
              view_module={@view_module}
              messages_stream={@streams.messages}
              oldest_cursor={@oldest_cursor}
              active_pty_agent_uri={@active_pty_agent_uri}
              empty_state?={@messages_empty?}
            />
          </:main_view>
        </SessionEditor.session_editor>

        <section
          :if={@debug_open and @cc_events != []}
          class="border-t border-zinc-200 dark:border-zinc-800 bg-zinc-50 dark:bg-zinc-950 max-h-48 overflow-y-auto p-3"
        >
          <h3 class="text-[10px] uppercase tracking-wide text-zinc-500 mb-1">
            Debug events (last 20)
          </h3>
          <ul class="space-y-1 text-[11px]">
            <li :for={ev <- @cc_events} class="flex gap-2">
              <span class={[
                "px-1 rounded font-semibold",
                ev.level == "error" && "bg-rose-100 dark:bg-rose-900 text-rose-700 dark:text-rose-300",
                ev.level == "warning" && "bg-amber-100 dark:bg-amber-900 text-amber-700 dark:text-amber-300",
                ev.level not in ["error", "warning"] && "bg-zinc-200 dark:bg-zinc-800 text-zinc-700 dark:text-zinc-300"
              ]}>{ev.level}</span>
              <span class="font-mono text-[10px] text-zinc-500">{ev.bridge_id}</span>
              <span class="flex-1">{ev.text}</span>
            </li>
          </ul>
        </section>
      </:main_window>

      <:right_sidebar>
        <MemberPanel.member_panel members={@session_members} />
      </:right_sidebar>
    </IdeShell.ide_shell>
    """
  end

  # Helper component: render whichever SessionView is active. We pull
  # the module out of assigns and call its `render/1` with the assigns
  # the view declares it needs.
  attr :view_module, :atom, required: true
  attr :messages_stream, :any, required: true
  attr :oldest_cursor, :any, default: nil
  attr :active_pty_agent_uri, :any, default: nil
  attr :empty_state?, :boolean, default: false

  defp render_active_view(assigns) do
    case assigns.view_module do
      mod when is_atom(mod) and not is_nil(mod) ->
        mod.render(assigns)

      _ ->
        # Fallback — should not happen because mount/3 always seeds
        # :current_view = :conversation and ConversationView is
        # registered by EzagentPluginLiveview.Application.start/2.
        ConversationView.render(assigns)
    end
  end

  # Compute the active view module from assigns. The render fn returns
  # the module so `render/1` can avoid recomputing per-render.
  defp resolve_view_render(%{current_view: view_id}) do
    case SessionViewRegistry.lookup(view_id) do
      {:ok, mod} -> mod
      :error -> ConversationView
    end
  end

  defp resolve_view_render(_), do: ConversationView

  # --- Helpers ----------------------------------------------------------

  # Bundle the per-session reads needed by SessionEditor + MemberPanel.
  defp assign_session_context(socket, session_uri) do
    members = read_session_members(session_uri)
    applicable = SessionViewRegistry.applicable_views(session_uri)

    socket
    |> assign(:session_members, members)
    |> assign(:member_options, Enum.map(members, & &1.uri) |> Enum.sort())
    |> assign(:floating_agents, list_floating_agents())
    |> assign(:applicable_views, applicable)
    |> assign(:view_module, view_module_for(applicable, current_view_or_default(socket)))
    |> assign(:session_info, build_session_info(session_uri, members))
    |> assign(:feishu_chat_ids, feishu_chat_ids_for(session_uri))
  end

  defp current_view_or_default(socket) do
    case Map.get(socket.assigns, :current_view) do
      nil -> :conversation
      v -> v
    end
  end

  defp view_module_for(applicable, current_view_id) do
    case Enum.find(applicable, &(&1.id == current_view_id)) do
      %{module: mod} ->
        mod

      nil ->
        case SessionViewRegistry.lookup(:conversation) do
          {:ok, mod} -> mod
          :error -> ConversationView
        end
    end
  end

  defp refresh_views_and_members(socket) do
    assign_session_context(socket, socket.assigns.current_session_uri)
  end

  defp build_session_info(%URI{} = session_uri, members) do
    workspace_str =
      case Ezagent.WorkspaceRegistry.lookup(session_uri) do
        {:ok, ws_uri} -> URI.to_string(ws_uri)
        :error -> nil
      end

    created_at =
      case Ezagent.MessageStore.recent_in_session(session_uri, 1) do
        [%Ezagent.Message{inserted_at: at}] -> at
        _ -> nil
      end

    %{
      member_count: length(members),
      workspace_uri: workspace_str,
      created_at: created_at
    }
  end

  defp feishu_chat_ids_for(%URI{} = session_uri) do
    if Code.ensure_loaded?(EzagentPluginFeishu.SessionBinding) do
      EzagentPluginFeishu.SessionBinding.chat_ids_for(session_uri)
    else
      []
    end
  end

  # `@<entity://...>` extraction. The autocomplete inserts a trailing
  # space, so `@uri ` is the canonical shape; permissive on EOL.
  defp parse_mentions(text) when is_binary(text) do
    ~r/@(entity:\/\/[^\s]+)/
    |> Regex.scan(text, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.flat_map(fn uri_str ->
      case URI.new(uri_str) do
        {:ok, uri} -> [uri]
        _ -> []
      end
    end)
  end

  defp parse_mentions(_), do: []

  defp safe_view_id(s) when is_binary(s) do
    {:ok, String.to_existing_atom(s)}
  rescue
    ArgumentError -> :error
  end

  defp safe_view_id(_), do: :error

  defp count_alive_agents do
    Ezagent.KindRegistry.list_all()
    |> Enum.count(fn {uri_str, _pid} -> String.starts_with?(uri_str, "entity://agent/") end)
  end

  defp count_connected_bridges do
    if Code.ensure_loaded?(EzagentPluginCc.BridgeRegistry) do
      length(EzagentPluginCc.BridgeRegistry.list_connected())
    else
      0
    end
  end

  defp ezagent_version do
    case Application.spec(:ezagent_core, :vsn) do
      nil -> "dev"
      vsn -> to_string(vsn)
    end
  end

  defp session_events_topic(%URI{} = uri),
    do: Ezagent.Behavior.Chat.session_events_topic(uri)

  defp load_session_messages(%URI{} = session_uri) do
    session_uri
    |> Ezagent.MessageStore.recent_in_session(@message_limit)
    |> Enum.reverse()
    |> Enum.map(&message_to_row/1)
  end

  defp oldest_cursor(rows) do
    case rows do
      [%{at: %DateTime{} = at} | _] -> at
      _ -> nil
    end
  end

  defp read_session_members(%URI{} = session_uri) do
    case Ezagent.KindRegistry.lookup(session_uri) do
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
    Ezagent.KindRegistry.list_all()
    |> Enum.filter(fn {uri_str, _pid} -> String.starts_with?(uri_str, "entity://agent/") end)
    |> Enum.map(fn {uri_str, _pid} -> uri_str end)
    |> Enum.sort()
  end

  defp list_floating_agents do
    all_agents = list_agent_uris() |> MapSet.new()

    joined =
      EzagentDomainChat.list_sessions()
      |> Enum.flat_map(fn session_uri ->
        read_session_members(session_uri) |> Enum.map(& &1.uri)
      end)
      |> MapSet.new()

    MapSet.difference(all_agents, joined) |> Enum.sort()
  end

  defp bridge_topic_safely, do: EzagentPluginCc.BridgeRegistry.topic()

  defp message_to_row(%Ezagent.Message{} = msg) do
    sender_str = URI.to_string(msg.sender)

    %{
      id: msg.id,
      sender: sender_str,
      sender_kind: sender_kind(sender_str),
      text: body_text(msg.body),
      attachments: body_attachments(msg.body),
      at: msg.inserted_at
    }
  end

  defp sender_kind(uri_str) do
    cond do
      String.starts_with?(uri_str, "entity://user/") -> :user
      String.starts_with?(uri_str, "entity://agent/") -> :agent
      true -> :other
    end
  end

  defp body_text(%{text: t}) when is_binary(t), do: t
  defp body_text(%{"text" => t}) when is_binary(t), do: t
  defp body_text(_), do: ""

  defp body_attachments(%{attachments: list}) when is_list(list), do: Enum.map(list, &att_to_link/1)
  defp body_attachments(%{"attachments" => list}) when is_list(list),
    do: Enum.map(list, &att_to_link/1)
  defp body_attachments(_), do: []

  defp att_to_link(%URI{scheme: "resource", host: "uploads", path: "/" <> filename}),
    do: {display_name(filename), "/admin/uploads/#{filename}"}

  defp att_to_link(%URI{} = uri),
    do: {URI.to_string(uri), URI.to_string(uri)}

  defp att_to_link(s) when is_binary(s) do
    case URI.parse(s) do
      %URI{} = uri -> att_to_link(uri)
      _ -> {s, s}
    end
  end

  defp display_name(<<_uuid::binary-size(36), "-", rest::binary>>), do: rest
  defp display_name(other), do: other

  defp ctx(socket) do
    %{
      caller: socket.assigns.caller_uri,
      caps: socket.assigns.caller_caps,
      reply: :ignore
    }
  end

  defp sanitize_filename(name) when is_binary(name) do
    name
    |> Path.basename()
    |> String.replace(~r/[^\w\.\-]+/, "_")
    |> String.slice(0, 200)
    |> case do
      "" -> "file"
      s -> s
    end
  end

  defp sanitize_filename(_), do: "file"

  defp send_chat_message(socket, text, attachments, mentions) do
    msg =
      Ezagent.Message.new(socket.assigns.caller_uri,
        %{text: text, attachments: attachments},
        mentions: mentions
      )

    target = URI.new!("#{URI.to_string(socket.assigns.current_session_uri)}?action=chat.send")

    inv = %Ezagent.Invocation{
      target: target,
      mode: :cast,
      args: %{message: msg},
      ctx: ctx(socket)
    }

    case Ezagent.Invocation.dispatch(inv) do
      :ok ->
        clear_compose(socket)

      {:ok, _} ->
        clear_compose(socket)

      {:error, reason} ->
        {:noreply, assign(socket, :flash_error, friendly_error("Send", reason))}
    end
  end

  defp clear_compose(socket) do
    {:noreply,
     socket
     |> assign(:flash_error, nil)
     |> assign(:compose_form, to_form(%{"text" => ""}, as: "chat"))}
  end

  defp friendly_error(_action, :unauthorized) do
    "You don't have permission for this action. Contact admin for cap grant."
  end

  defp friendly_error(action, reason), do: "#{action} failed: #{inspect(reason)}"
end
