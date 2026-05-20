defmodule EzagentDomainUi.IdeShell do
  @moduledoc """
  Phase 8 — Agent IDE Shell layout components.

  Stateless Phoenix.Component layout primitives that wrap any LiveView
  in the IDE-style Activity Bar / Resource Panel / Top Command Bar /
  Main Window / Right Sidebar / Status Bar topology.

  Per Phase 8 spec §2 decision D1, these are functional components,
  not LiveComponents. State (which Activity is active, what's in the
  resource panel, etc.) is owned by the wrapping LiveView and passed
  down as attrs.

  Per decision D2, the active Activity is derived from the current URL,
  not socket state. Use `EzagentDomainUi.IdeShell.activity_for_path/1`
  to compute it.

  Phase 8 polish (Allen 2026-05-20):
  - 6 Activity items (Settings moved under the avatar dropdown).
  - Top bar shows avatar + dropdown trigger; no workspace label.
  - Business routes live at top level (`/sessions`, `/workspaces`,
    `/identities`, `/routing`, `/plugins`). `/admin/*` is reserved
    for the sysadmin Dashboard.

  ## Usage

      <.ide_shell
        current_entity_uri={@current_entity_uri}
        current_path={@socket.assigns.current_path}
        status={@status}
      >
        <:resource_panel>
          <.tree_list>...</.tree_list>
        </:resource_panel>
        <:main_window>
          <.editor_tabs items={@tabs} selected={@active_tab} />
          ... main content ...
        </:main_window>
        <:right_sidebar>
          <.member_roster members={@members} />
        </:right_sidebar>
      </.ide_shell>
  """

  use Phoenix.Component
  use EzagentDomainUi.Primitives
  alias Phoenix.LiveView.JS

  # --- ide_shell -------------------------------------------------------------

  attr :current_entity_uri, :any, required: true
  attr :current_path, :string, required: true
  attr :status, :map, default: %{}
  slot :resource_panel
  slot :main_window, required: true
  slot :right_sidebar
  slot :command_palette

  def ide_shell(assigns) do
    ~H"""
    <div
      id="ide-shell"
      class="fixed inset-0 flex flex-col bg-zinc-50 text-zinc-900 text-sm font-sans"
    >
      <.top_command_bar current_entity_uri={@current_entity_uri} />

      <div class="flex-1 flex min-h-0">
        <.activity_bar current_path={@current_path} />

        <div :if={@resource_panel != []} class="w-56 border-r border-zinc-200 bg-white overflow-y-auto">
          {render_slot(@resource_panel)}
        </div>

        <div class="flex-1 flex flex-col min-w-0 bg-white">
          {render_slot(@main_window)}
        </div>

        <div :if={@right_sidebar != []} id="right-sidebar" class="w-72 border-l border-zinc-200 bg-white overflow-y-auto hidden lg:block">
          {render_slot(@right_sidebar)}
        </div>
      </div>

      <.status_bar
        current_entity_uri={@current_entity_uri}
        status={@status}
      />

      {render_slot(@command_palette)}
    </div>
    """
  end

  # --- activity_bar ----------------------------------------------------------

  @doc """
  Vertical icon strip on the left edge. 6 top-level Activities.
  """
  attr :current_path, :string, required: true

  def activity_bar(assigns) do
    items = activity_items()
    active_key = activity_for_path(assigns.current_path)
    assigns = assign(assigns, :items, items) |> assign(:active_key, active_key)

    ~H"""
    <nav class="w-12 border-r border-zinc-200 bg-zinc-100 flex flex-col items-center py-2 gap-1">
      <a
        :for={item <- @items}
        href={item.path}
        class={[
          "w-10 h-10 flex items-center justify-center rounded-md transition-colors",
          item.key == @active_key
            && "bg-white shadow-sm text-zinc-900"
            || "text-zinc-500 hover:bg-zinc-200 hover:text-zinc-700"
        ]}
        title={item.label}
        aria-label={item.label}
      >
        <.icon name={item.icon} size="md" />
      </a>
    </nav>
    """
  end

  @doc """
  List of all 6 Activity Bar items in display order.

  Phase 8 polish (2026-05-20): Settings is no longer a top-level
  Activity — it moved under the avatar dropdown. The 6 items are
  business features (Sessions / Workspaces / Identities / Routing /
  Plugins) plus the admin Dashboard.
  """
  def activity_items do
    [
      %{key: :sessions, label: "Sessions", icon: "message-square", path: "/sessions"},
      %{key: :workspaces, label: "Workspaces", icon: "folder", path: "/workspaces"},
      %{key: :identities, label: "Identities", icon: "users", path: "/identities"},
      %{key: :routing, label: "Routing", icon: "route", path: "/routing"},
      %{key: :plugins, label: "Plugins", icon: "puzzle", path: "/plugins"},
      %{key: :dashboard, label: "Dashboard", icon: "dashboard", path: "/admin"}
    ]
  end

  @doc """
  Compute which Activity is "active" based on the current path.

  Examples:

      iex> activity_for_path("/sessions")
      :sessions

      iex> activity_for_path("/workspaces/demo")
      :workspaces

      iex> activity_for_path("/admin/logs")
      :dashboard
  """
  def activity_for_path(path) when is_binary(path) do
    cond do
      String.starts_with?(path, "/sessions") -> :sessions
      String.starts_with?(path, "/workspaces") -> :workspaces
      String.starts_with?(path, "/identities") -> :identities
      String.starts_with?(path, "/routing") -> :routing
      String.starts_with?(path, "/plugins") -> :plugins
      String.starts_with?(path, "/admin") -> :dashboard
      String.starts_with?(path, "/profile") -> :sessions
      String.starts_with?(path, "/settings") -> :sessions
      true -> :sessions
    end
  end

  def activity_for_path(_), do: :sessions

  # --- top_command_bar -------------------------------------------------------

  attr :current_entity_uri, :any, required: true

  def top_command_bar(assigns) do
    ~H"""
    <header class="h-10 border-b border-zinc-200 bg-white px-3 flex items-center gap-3 shrink-0">
      <div class="flex items-center gap-2 shrink-0">
        <span class="font-semibold text-xs tracking-tight">ezagent</span>
      </div>

      <div class="flex-1 max-w-md mx-auto">
        <button
          type="button"
          phx-click={JS.dispatch("ezagent:open-command-palette")}
          class="w-full flex items-center gap-2 px-3 py-1.5 bg-zinc-100 hover:bg-zinc-200 rounded-md text-xs text-zinc-500 transition-colors"
        >
          <.icon name="search" size="xs" />
          <span>搜索 sessions / entities / actions ...</span>
          <span class="ml-auto text-[10px] text-zinc-400 font-mono">⌘K</span>
        </button>
      </div>

      <div class="flex items-center gap-2 shrink-0">
        <.icon name="bell" size="sm" class="text-zinc-500 hover:text-zinc-700 cursor-pointer" />
        <.icon name="help" size="sm" class="text-zinc-500 hover:text-zinc-700 cursor-pointer" />
        <.avatar_menu current_entity_uri={@current_entity_uri} />
      </div>
    </header>
    """
  end

  # --- avatar_menu -----------------------------------------------------------

  @doc """
  Right-corner avatar button + dropdown menu (Phase 8 polish #5,
  Allen 2026-05-20).

  Replaces the prior `<.uri_chip>` in `top_command_bar/1`. Dropdown
  shows Profile / Settings / Sign out links. Menu visibility is
  handled by `Phoenix.LiveView.JS.toggle/1` — no LV state needed
  because the menu is purely presentational.

  Tooltip on the avatar shows "Your profile".
  """
  attr :current_entity_uri, :any, required: true

  def avatar_menu(assigns) do
    assigns =
      assigns
      |> assign_new(:menu_id, fn -> "avatar-menu" end)
      |> assign(:uri_str, format_uri_for_status(assigns.current_entity_uri))

    ~H"""
    <div class="relative">
      <button
        type="button"
        phx-click={JS.toggle(to: "##{@menu_id}")}
        title="Your profile"
        aria-label="Your profile"
        class="flex items-center"
      >
        <.avatar uri={@current_entity_uri} size="sm" />
      </button>

      <div
        id={@menu_id}
        class="hidden absolute right-0 top-full mt-1 w-64 bg-white border border-zinc-200 rounded-md shadow-lg z-40"
      >
        <div class="px-3 py-3 border-b border-zinc-200 flex items-center gap-2">
          <.avatar uri={@current_entity_uri} size="md" />
          <div class="flex-1 min-w-0">
            <div class="font-mono text-[11px] text-zinc-700 truncate">{@uri_str}</div>
            <div class="flex items-center gap-1 text-[10px] text-zinc-500 mt-0.5">
              <.status_dot color="green" />
              <span>online</span>
            </div>
          </div>
        </div>
        <div class="py-1">
          <a
            href="/profile"
            class="block px-3 py-1.5 text-xs text-zinc-700 hover:bg-zinc-100"
          >Profile</a>
          <a
            href="/settings"
            class="block px-3 py-1.5 text-xs text-zinc-700 hover:bg-zinc-100"
          >Settings</a>
        </div>
        <div class="border-t border-zinc-200 py-1">
          <form action="/logout" method="post" class="block">
            <input
              type="hidden"
              name="_csrf_token"
              value={Plug.CSRFProtection.get_csrf_token()}
            />
            <button
              type="submit"
              class="w-full text-left px-3 py-1.5 text-xs text-rose-600 hover:bg-zinc-100"
            >Sign out</button>
          </form>
        </div>
      </div>
    </div>
    """
  end

  # --- status_bar ------------------------------------------------------------

  attr :current_entity_uri, :any, required: true
  attr :status, :map, default: %{}

  def status_bar(assigns) do
    ~H"""
    <footer class="h-6 border-t border-zinc-200 bg-zinc-50 px-3 flex items-center gap-4 text-[11px] text-zinc-600 shrink-0">
      <span class="flex items-center gap-1">
        <.icon name="users" size="xs" />
        <span class="font-mono">{format_uri_for_status(@current_entity_uri)}</span>
      </span>
      <span :if={Map.get(@status, :session_uri)} class="flex items-center gap-1">
        <.icon name="message-square" size="xs" />
        <span class="font-mono">{format_uri_for_status(@status.session_uri)}</span>
      </span>
      <span class="flex items-center gap-1">
        <.status_dot color="green" />
        <span>{Map.get(@status, :agents_alive, 0)} agents</span>
      </span>
      <span class="flex items-center gap-1">
        <.status_dot color={(Map.get(@status, :bridges, 0) > 0) && "green" || "gray"} />
        <span>{Map.get(@status, :bridges, 0)} bridges</span>
      </span>
      <a href="/admin/logs" class="flex items-center gap-1 hover:text-zinc-900 ml-auto">
        <.icon name="bug" size="xs" />
        <span>{Map.get(@status, :debug_events, 0)} events</span>
      </a>
      <span class="text-zinc-400">v{Map.get(@status, :version, "dev")}</span>
    </footer>
    """
  end

  defp format_uri_for_status(%URI{} = uri), do: URI.to_string(uri)
  defp format_uri_for_status(s) when is_binary(s), do: s
  defp format_uri_for_status(nil), do: "—"
  defp format_uri_for_status(_), do: "—"

  # --- editor_tabs -----------------------------------------------------------

  @doc """
  Tab strip at the top of Main Window.

      <.editor_tabs items={[{:session, "main"}, {:terminal, "cc_demo"}]} selected={:session} />
  """
  attr :items, :list, required: true
  attr :selected, :any, required: true
  attr :on_select, :string, default: "select_editor_tab"
  attr :on_close, :string, default: "close_editor_tab"

  def editor_tabs(assigns) do
    ~H"""
    <div class="flex items-center gap-px border-b border-zinc-200 bg-zinc-50 px-2 shrink-0">
      <div
        :for={{key, label} <- @items}
        class={[
          "flex items-center gap-1 px-3 py-1.5 text-xs font-medium border-b-2 cursor-pointer",
          to_string(key) == to_string(@selected)
            && "border-zinc-900 text-zinc-900 bg-white"
            || "border-transparent text-zinc-500 hover:text-zinc-700 hover:bg-zinc-100"
        ]}
        phx-click={@on_select}
        phx-value-key={inspect(key)}
      >
        <span>{label}</span>
        <button
          type="button"
          phx-click={@on_close}
          phx-value-key={inspect(key)}
          class="opacity-50 hover:opacity-100 text-[10px]"
        >
          ✕
        </button>
      </div>
    </div>
    """
  end

  # --- split_pane ------------------------------------------------------------

  @doc """
  Optional vertical or horizontal split between two slots.
  """
  attr :open, :boolean, default: false
  attr :direction, :string, default: "vertical", values: ~w(vertical horizontal)
  slot :primary, required: true
  slot :secondary

  def split_pane(assigns) do
    ~H"""
    <div class={[
      "flex flex-1 min-h-0 min-w-0",
      @direction == "vertical" && "flex-row" || "flex-col"
    ]}>
      <div class={["flex-1 min-h-0 min-w-0", @open && @secondary != [] && "border-r border-zinc-200"]}>
        {render_slot(@primary)}
      </div>
      <div
        :if={@open && @secondary != []}
        class="flex-1 min-h-0 min-w-0"
      >
        {render_slot(@secondary)}
      </div>
    </div>
    """
  end

  # --- command_palette -------------------------------------------------------

  @doc """
  Command palette modal — triggered by ⌘K or CmdK button in TopCommandBar.
  """
  attr :open, :boolean, default: false
  attr :query, :string, default: ""
  attr :results, :list, default: []

  def command_palette(assigns) do
    ~H"""
    <div
      id="command-palette"
      class={[
        "fixed inset-0 z-50 flex items-start justify-center pt-20",
        not @open && "hidden"
      ]}
      phx-window-keydown="close_command_palette"
      phx-key="escape"
    >
      <div
        class="absolute inset-0 bg-zinc-900/40 backdrop-blur-sm"
        phx-click="close_command_palette"
      />
      <div class="relative z-10 w-full max-w-xl mx-4 bg-white rounded-lg shadow-2xl overflow-hidden">
        <form phx-change="command_query" phx-submit="command_select">
          <input
            type="text"
            name="q"
            value={@query}
            placeholder="搜索 sessions / entities / actions ..."
            autocomplete="off"
            autofocus
            class="w-full px-4 py-3 text-sm border-b border-zinc-200 focus:outline-none"
          />
        </form>
        <div class="max-h-96 overflow-y-auto">
          <div :if={@results == []} class="px-4 py-8 text-center text-xs text-zinc-500">
            {@query == "" && "输入开始搜索" || "没有结果"}
          </div>
          <button
            :for={r <- @results}
            type="button"
            phx-click="command_select_result"
            phx-value-key={r.key}
            class="w-full px-4 py-2 text-left text-xs hover:bg-zinc-100 flex items-center gap-2 border-b border-zinc-100"
          >
            <.icon name={r.icon || "dot"} size="xs" />
            <span class="font-mono">{r.label}</span>
            <span :if={Map.get(r, :group)} class="ml-auto text-[10px] text-zinc-400 uppercase">{r.group}</span>
          </button>
        </div>
      </div>
    </div>
    """
  end
end
