defmodule EzagentPluginLiveview.Admin.SessionEditor do
  @moduledoc """
  Phase 8b — Main Window's Session editor.

  Stateless Phoenix.Component composing:

    1. `session_header/1` — session selector + create + view-switcher + setting dropdown
    2. `:main_view` slot — the active SessionView's `render/1` output
    3. `message_composer/1` — input with @ autocomplete + file upload + send

  Replaces Phase 4a's `EzagentPluginLiveview.Admin.ChatWindow` which
  hard-coded a single "session header + message stream + compose"
  layout. The view-switcher is now plugin-driven (Phase 8b §1.2).

  Parent (admin_live) owns all assigns + event handlers. This module
  is a pure renderer.
  """

  use Phoenix.Component
  use EzagentDomainUi.Primitives
  alias Phoenix.LiveView.JS

  attr :current_session_uri, URI, required: true
  attr :sessions, :list, required: true
  attr :applicable_views, :list, required: true
  attr :current_view, :atom, required: true
  attr :new_session_form, :map, required: true
  attr :compose_form, :map, required: true
  attr :member_options, :list, required: true
  attr :session_info, :map, required: true
  attr :feishu_chat_ids, :list, default: []
  attr :debug_open, :boolean, default: false
  attr :uploads, :map, default: nil
  attr :flash_error, :string, default: nil
  slot :main_view, required: true

  def session_editor(assigns) do
    ~H"""
    <div id="session-editor" class="flex-1 flex flex-col min-h-0">
      <.session_header
        current_session_uri={@current_session_uri}
        sessions={@sessions}
        applicable_views={@applicable_views}
        current_view={@current_view}
        new_session_form={@new_session_form}
        session_info={@session_info}
        feishu_chat_ids={@feishu_chat_ids}
        debug_open={@debug_open}
      />

      <div class="flex-1 flex flex-col min-h-0">
        {render_slot(@main_view)}
      </div>

      <.message_composer
        compose_form={@compose_form}
        member_options={@member_options}
        uploads={@uploads}
        flash_error={@flash_error}
      />
    </div>
    """
  end

  # --- session_header -------------------------------------------------------

  attr :current_session_uri, URI, required: true
  attr :sessions, :list, required: true
  attr :applicable_views, :list, required: true
  attr :current_view, :atom, required: true
  attr :new_session_form, :map, required: true
  attr :session_info, :map, required: true
  attr :feishu_chat_ids, :list, default: []
  attr :debug_open, :boolean, default: false

  defp session_header(assigns) do
    ~H"""
    <header class="flex items-center gap-2 px-3 py-2 border-b border-zinc-200 bg-white shrink-0">
      <.session_selector current_session_uri={@current_session_uri} sessions={@sessions} />
      <.create_session_button new_session_form={@new_session_form} />

      <div class="flex-1" />

      <.view_switcher applicable_views={@applicable_views} current_view={@current_view} />
      <.setting_dropdown
        current_session_uri={@current_session_uri}
        session_info={@session_info}
        feishu_chat_ids={@feishu_chat_ids}
        debug_open={@debug_open}
      />
    </header>
    """
  end

  # --- session_selector -----------------------------------------------------

  attr :current_session_uri, URI, required: true
  attr :sessions, :list, required: true

  defp session_selector(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <span class="text-[10px] uppercase tracking-wide text-zinc-500">Session</span>
      <form phx-change="switch_session" class="contents">
        <select
          name="session_uri"
          id="session-selector"
          class="text-xs font-mono px-2 py-1 border border-zinc-300 rounded bg-white"
        >
          <option
            :for={uri <- @sessions}
            value={URI.to_string(uri)}
            selected={URI.to_string(uri) == URI.to_string(@current_session_uri)}
          >
            {URI.to_string(uri)}
          </option>
        </select>
      </form>
    </div>
    """
  end

  # --- create_session_button ------------------------------------------------

  attr :new_session_form, :map, required: true

  defp create_session_button(assigns) do
    ~H"""
    <details class="relative">
      <summary class="cursor-pointer text-xs text-blue-600 hover:text-blue-700 select-none">
        + New
      </summary>
      <div class="absolute left-0 top-full mt-1 w-64 bg-white border border-zinc-200 rounded-md shadow-lg z-30 p-2">
        <.form for={@new_session_form} phx-submit="create_session">
          <label for="new_session_short_name" class="block text-[10px] text-zinc-500 mb-1">
            New session name
          </label>
          <input
            type="text"
            name="new_session[short_name]"
            id="new_session_short_name"
            placeholder="architect-review"
            class="w-full text-xs px-2 py-1 border border-zinc-300 rounded"
          />
          <button
            type="submit"
            class="mt-2 w-full px-2 py-1 bg-blue-600 text-white text-xs rounded hover:bg-blue-700"
          >
            Create
          </button>
        </.form>
      </div>
    </details>
    """
  end

  # --- view_switcher --------------------------------------------------------

  attr :applicable_views, :list, required: true
  attr :current_view, :atom, required: true

  defp view_switcher(assigns) do
    ~H"""
    <div id="view-switcher" class="flex items-center gap-px border border-zinc-300 rounded overflow-hidden">
      <button
        :for={view <- @applicable_views}
        type="button"
        phx-click="switch_view"
        phx-value-view={view.id}
        class={[
          "flex items-center gap-1 px-2 py-1 text-xs",
          view.id == @current_view
            && "bg-zinc-900 text-white"
            || "bg-white text-zinc-600 hover:bg-zinc-100"
        ]}
        title={view.label}
      >
        <.icon name={view.icon} size="xs" />
        <span>{view.label}</span>
      </button>
    </div>
    """
  end

  # --- setting_dropdown -----------------------------------------------------

  attr :current_session_uri, URI, required: true
  attr :session_info, :map, required: true
  attr :feishu_chat_ids, :list, default: []
  attr :debug_open, :boolean, default: false

  defp setting_dropdown(assigns) do
    routing_href = "/routing?session=" <> URI.encode_www_form(URI.to_string(assigns.current_session_uri))
    assigns = assign(assigns, :routing_href, routing_href)

    ~H"""
    <div class="relative">
      <button
        type="button"
        phx-click={JS.toggle(to: "#session-setting-menu")}
        title="Session settings"
        aria-label="Session settings"
        class="p-1 text-zinc-500 hover:text-zinc-900 hover:bg-zinc-100 rounded"
      >
        <.icon name="settings" size="sm" />
      </button>

      <div
        id="session-setting-menu"
        class="hidden absolute right-0 top-full mt-1 w-80 bg-white border border-zinc-200 rounded-md shadow-lg z-40 text-xs"
      >
        <div class="px-3 py-2 border-b border-zinc-200">
          <div class="text-[10px] uppercase tracking-wide text-zinc-500">Session</div>
          <div class="font-mono text-zinc-800 break-all mt-0.5">{URI.to_string(@current_session_uri)}</div>
        </div>

        <div class="px-3 py-2 border-b border-zinc-200">
          <label class="flex items-center justify-between cursor-pointer">
            <div class="flex items-center gap-2">
              <.icon name="bug" size="xs" />
              <span class="text-zinc-700">Debug events panel</span>
            </div>
            <button
              type="button"
              phx-click="toggle_debug_panel"
              class={[
                "relative inline-flex h-4 w-7 items-center rounded-full transition-colors",
                @debug_open && "bg-emerald-600" || "bg-zinc-300"
              ]}
            >
              <span class={[
                "inline-block h-3 w-3 transform rounded-full bg-white transition-transform",
                @debug_open && "translate-x-3.5" || "translate-x-0.5"
              ]} />
            </button>
          </label>
        </div>

        <div class="px-3 py-2 border-b border-zinc-200">
          <div class="flex items-center gap-2 mb-1">
            <.icon name="message-square" size="xs" />
            <span class="text-[10px] uppercase tracking-wide text-zinc-500">Feishu binding</span>
          </div>
          <div :if={@feishu_chat_ids == []} class="text-zinc-500 italic">
            no chat bound — bind via mix ezagent.feishu.chat.bind
          </div>
          <ul :if={@feishu_chat_ids != []} class="space-y-1">
            <li :for={chat_id <- @feishu_chat_ids} class="flex items-center justify-between gap-2">
              <code class="text-[10px] truncate text-zinc-700">{chat_id}</code>
              <button
                type="button"
                phx-click="unbind_feishu_chat"
                phx-value-chat_id={chat_id}
                data-confirm={"Unbind Feishu chat #{chat_id} from this session?"}
                class="text-[10px] text-rose-600 hover:text-rose-700"
              >
                Unbind
              </button>
            </li>
          </ul>
        </div>

        <div class="px-3 py-2 border-b border-zinc-200">
          <a
            href={@routing_href}
            class="flex items-center gap-2 text-blue-600 hover:text-blue-700"
          >
            <.icon name="route" size="xs" />
            <span>Routing rules for this session</span>
          </a>
        </div>

        <div class="px-3 py-2">
          <div class="text-[10px] uppercase tracking-wide text-zinc-500 mb-1">Info</div>
          <dl class="space-y-0.5 text-zinc-700">
            <div class="flex justify-between"><dt>members</dt><dd>{@session_info[:member_count] || 0}</dd></div>
            <div class="flex justify-between"><dt>workspace</dt><dd class="font-mono text-[10px] truncate max-w-[60%]">{@session_info[:workspace_uri] || "—"}</dd></div>
            <div class="flex justify-between"><dt>created</dt><dd class="text-[10px]">{format_dt(@session_info[:created_at])}</dd></div>
          </dl>
        </div>
      </div>
    </div>
    """
  end

  defp format_dt(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  defp format_dt(_), do: "—"

  # --- message_composer -----------------------------------------------------

  attr :compose_form, :map, required: true
  attr :member_options, :list, required: true
  attr :uploads, :map, default: nil
  attr :flash_error, :string, default: nil

  defp message_composer(assigns) do
    members_json = Jason.encode!(assigns.member_options)
    assigns = assign(assigns, :members_json, members_json)

    ~H"""
    <.form
      for={@compose_form}
      phx-submit="chat_compose"
      phx-change="validate_compose"
      class="border-t border-zinc-200 bg-white p-3 space-y-2 shrink-0"
    >
      <div
        id="mention-popover"
        class="hidden absolute z-50 bg-white border border-zinc-300 rounded-md shadow-lg max-h-48 overflow-y-auto"
      ></div>

      <div class="flex gap-2 items-center">
        <input
          type="text"
          name="chat[text]"
          id="chat-compose-input"
          phx-hook="MentionAutocomplete"
          data-members={@members_json}
          data-popover="#mention-popover"
          autocomplete="off"
          placeholder="Type a message... use @ to mention a member"
          class="flex-1 px-3 py-2 border border-zinc-300 rounded-md text-sm focus:outline-none focus:border-blue-400"
        />

        <div :if={@uploads}>
          <label
            for={@uploads.attachments.ref}
            class="inline-flex items-center px-3 py-2 border border-zinc-300 rounded-md text-sm cursor-pointer hover:bg-zinc-50"
            title="Attach files (≤10MB each, up to 5)"
          >
            📎
          </label>
          <.live_file_input upload={@uploads.attachments} class="hidden" />
        </div>

        <button
          type="submit"
          id="chat-send-btn"
          class="px-4 py-2 bg-emerald-600 text-white rounded-md text-sm font-medium hover:bg-emerald-700"
        >
          Send
        </button>
      </div>

      <div :if={@uploads && @uploads.attachments.entries != []} class="flex flex-wrap gap-1">
        <div
          :for={entry <- @uploads.attachments.entries}
          class="inline-flex items-center gap-1 px-2 py-0.5 bg-blue-50 border border-blue-200 rounded text-[11px]"
        >
          <span>📎 {entry.client_name}</span>
          <span class="text-zinc-500">{progress_label(entry)}</span>
          <button
            type="button"
            phx-click="cancel_upload"
            phx-value-ref={entry.ref}
            aria-label={"cancel " <> entry.client_name}
            class="text-rose-600 hover:text-rose-700"
          >
            ×
          </button>
        </div>
        <div :for={err <- my_upload_errors(@uploads.attachments)} class="basis-full text-rose-600 text-[11px]">
          {format_upload_error(err)}
        </div>
      </div>

      <p :if={@flash_error} class="text-xs text-rose-600">{@flash_error}</p>
    </.form>
    """
  end

  defp progress_label(%{progress: 100}), do: "✓"
  defp progress_label(%{progress: p}) when is_integer(p) and p > 0, do: "#{p}%"
  defp progress_label(_), do: ""

  defp my_upload_errors(%{errors: errors}) when is_list(errors), do: errors
  defp my_upload_errors(_), do: []

  defp format_upload_error({_ref, :too_large}), do: "file too large (max 10MB)"
  defp format_upload_error({_ref, :too_many_files}), do: "too many files (max 5)"
  defp format_upload_error({_ref, reason}), do: "upload error: #{inspect(reason)}"
end
