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
  attr :workspace_name, :string, default: "default"
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
      <.top_command_bar
        current_entity_uri={@current_entity_uri}
        workspace_name={@workspace_name}
      />

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
        workspace_name={@workspace_name}
        status={@status}
      />

      {render_slot(@command_palette)}
    </div>
    """
  end

  # --- activity_bar ----------------------------------------------------------

  @doc """
  Vertical icon strip on the left edge. 7 top-level Activities.
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

  @doc "List of all 7 Activity Bar items in display order."
  def activity_items do
    [
      %{key: :sessions, label: "Sessions", icon: "message-square", path: "/admin"},
      %{key: :workspaces, label: "Workspaces", icon: "folder", path: "/admin/workspaces"},
      %{key: :identities, label: "Identities", icon: "users", path: "/admin/entities"},
      %{key: :routing, label: "Routing", icon: "route", path: "/admin/routing"},
      %{key: :plugins, label: "Plugins", icon: "puzzle", path: "/admin/feishu/bindings"},
      %{key: :observability, label: "Observability", icon: "activity", path: "/admin/observability"},
      %{key: :settings, label: "Settings", icon: "settings", path: "/admin/settings"}
    ]
  end

  @doc """
  Compute which Activity is "active" based on the current path.

  Examples:

      iex> activity_for_path("/admin")
      :sessions

      iex> activity_for_path("/admin/workspaces/demo")
      :workspaces

      iex> activity_for_path("/admin/observability")
      :observability
  """
  def activity_for_path(path) when is_binary(path) do
    cond do
      path == "/admin" -> :sessions
      String.starts_with?(path, "/admin/workspaces") -> :workspaces
      String.starts_with?(path, "/admin/entities") -> :identities
      String.starts_with?(path, "/admin/agents") -> :identities
      String.starts_with?(path, "/admin/users") -> :identities
      String.starts_with?(path, "/admin/routing") -> :routing
      String.starts_with?(path, "/admin/feishu") -> :plugins
      String.starts_with?(path, "/admin/auto") -> :plugins
      String.starts_with?(path, "/admin/observability") -> :observability
      String.starts_with?(path, "/admin/snapshots") -> :observability
      String.starts_with?(path, "/admin/settings") -> :settings
      true -> :sessions
    end
  end

  def activity_for_path(_), do: :sessions

  # --- top_command_bar -------------------------------------------------------

  attr :current_entity_uri, :any, required: true
  attr :workspace_name, :string, default: "default"

  def top_command_bar(assigns) do
    ~H"""
    <header class="h-10 border-b border-zinc-200 bg-white px-3 flex items-center gap-3 shrink-0">
      <div class="flex items-center gap-2 shrink-0">
        <span class="font-semibold text-xs tracking-tight">ezagent</span>
        <span class="text-zinc-300">/</span>
        <span class="text-xs text-zinc-600 font-mono">{@workspace_name}</span>
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
        <.uri_chip uri={@current_entity_uri} />
      </div>
    </header>
    """
  end

  # --- status_bar ------------------------------------------------------------

  attr :current_entity_uri, :any, required: true
  attr :workspace_name, :string, default: "default"
  attr :status, :map, default: %{}

  def status_bar(assigns) do
    ~H"""
    <footer class="h-6 border-t border-zinc-200 bg-zinc-50 px-3 flex items-center gap-4 text-[11px] text-zinc-600 shrink-0">
      <span class="flex items-center gap-1">
        <.icon name="users" size="xs" />
        <span class="font-mono">{format_uri_for_status(@current_entity_uri)}</span>
      </span>
      <span class="flex items-center gap-1">
        <.icon name="folder" size="xs" />
        <span class="font-mono">{@workspace_name}</span>
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
      <a href="/admin/observability" class="flex items-center gap-1 hover:text-zinc-900 ml-auto">
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

  Default is single pane (no split). User opts in via state flag.

      <.split_pane open={@split_open} direction="vertical">
        <:primary>chat...</:primary>
        <:secondary>terminal...</:secondary>
      </.split_pane>
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

      <.command_palette
        open={@command_palette_open}
        query={@command_query}
        results={@command_results}
      />
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
