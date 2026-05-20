defmodule EzagentDomainUi.AdminSettingsShell do
  @moduledoc """
  Phase 8c PR-F (Allen 2026-05-20) — three-layer architecture pivot:
  admin as settings drawer.

  Before PR-F: `/admin/*` rendered inside `EzagentDomainUi.IdeShell`,
  positioning admin as a peer Activity Bar item alongside Sessions /
  Workspaces / etc. This conflated two orthogonal dimensions —
  permission/role vs workflow — and bloated the Activity Bar with a
  non-workflow surface.

  After PR-F: `/admin/*` renders in this shell, which is a "settings
  drawer" perspective opened from the avatar dropdown. Visual model
  mirrors macOS System Settings / VS Code Settings — left sidebar nav
  selects a sub-section, main area holds the panel, no app chrome
  above (no Activity Bar, no status bar).

  ## Three layers (Allen's 2026-05-20 pivot)

  - **system layer** — `/admin/*`. Sysadmin surfaces; doesn't depend
    on a workspace. Rendered by THIS shell.
  - **workspace layer** — `/sessions`, `/workspaces`, `/identities`,
    `/routing`, `/plugins`. Business workflow. Rendered by
    `EzagentDomainUi.IdeShell`.
  - **session layer** — the chat surface inside `/sessions`. Owned
    by `EzagentPluginLiveview.Admin.SessionEditor`.

  ## Usage

      <.admin_settings_shell
        current_entity_uri={@current_entity_uri}
        current_path={@current_path}
        active_section={:logs}
      >
        <:main>
          <.page_header title="Logs & Audit" />
          ...
        </:main>
      </.admin_settings_shell>

  Sub-sections are fixed in `sections/0`. `active_section` is one of
  `:overview | :logs | :registry | :snapshots` (the keys returned by
  `sections/0`) and controls which sidebar item is highlighted.
  """

  use Phoenix.Component
  use EzagentDomainUi.Primitives

  # --- admin_settings_shell -------------------------------------------------

  attr(:current_entity_uri, :any, required: true)

  attr(:current_path, :string,
    default: "/admin",
    doc: "Current request path. Used as a fallback to derive active_section if not given."
  )

  attr(:active_section, :atom,
    default: nil,
    doc: """
    Which sidebar item is highlighted. One of `:overview | :workspaces |
    :logs | :registry | :snapshots`, OR `nil` to derive from `current_path`.

    PR-M (Allen 2026-05-20): `:workspaces` added — `/workspaces*` is now
    a configuration surface (workspace management = templates / members
    / routing config), rendered inside this drawer rather than as a peer
    workflow surface in `IdeShell`. The "no two header types" UX rule.
    """
  )

  attr(:back_href, :string,
    default: "/sessions",
    doc: "Where the top-bar Back link returns to. Defaults to /sessions (the workspace layer)."
  )

  slot(:main, required: true)

  def admin_settings_shell(assigns) do
    active = assigns.active_section || section_for_path(assigns.current_path)
    assigns = assign(assigns, :active_section, active)

    ~H"""
    <div
      id="admin-settings-shell"
      class="fixed inset-0 flex flex-col bg-zinc-50 dark:bg-zinc-950 text-zinc-900 dark:text-zinc-100 text-sm font-sans"
    >
      <%!-- Top bar: Back to ezagent (left) + centered title +
            close X (right, same target as Back). --%>
      <header
        id="admin-settings-topbar"
        class="h-10 border-b border-zinc-200 dark:border-zinc-800 bg-white dark:bg-zinc-900 px-3 flex items-center shrink-0"
      >
        <div class="flex-1 flex items-center gap-2">
          <%!-- Phase 8c follow-up (Allen 2026-05-20) — mobile toggle for
                the admin sidebar nav. Mirrors the IdeShell pattern. --%>
          <button
            type="button"
            phx-click={Phoenix.LiveView.JS.toggle(to: "#admin-settings-sidebar", display: "flex")}
            class="lg:hidden p-1 rounded hover:bg-zinc-100 dark:hover:bg-zinc-800 text-zinc-500"
            title="Toggle settings nav"
            aria-label="Toggle settings nav"
          >
            <.icon name="folder" size="sm" />
          </button>
          <a
            href={@back_href}
            class="inline-flex items-center gap-1 px-2 py-1 -ml-1 rounded text-xs text-zinc-600 dark:text-zinc-400 hover:text-zinc-900 dark:hover:text-zinc-100 hover:bg-zinc-100 dark:hover:bg-zinc-800 transition-colors"
          >
            <.icon name="chevron-left" size="xs" />
            <span>Back to ezagent</span>
          </a>
        </div>
        <div class="flex-1 text-center">
          <span class="font-semibold text-xs tracking-tight">Admin Settings</span>
        </div>
        <div class="flex-1 flex items-center justify-end">
          <a
            href={@back_href}
            title="Close"
            aria-label="Close admin settings"
            class="inline-flex items-center justify-center w-7 h-7 rounded text-zinc-500 hover:text-zinc-900 dark:hover:text-zinc-100 hover:bg-zinc-100 dark:hover:bg-zinc-800 transition-colors"
          >
            <.icon name="x" size="sm" />
          </a>
        </div>
      </header>

      <%!-- Body: left sidebar (sub-section nav) + main panel.
            No Activity Bar (left edge), no status bar (bottom) — admin
            is a "drawer" perspective, not the workspace. --%>
      <div class="flex-1 flex min-h-0">
        <.sidebar_nav active_section={@active_section} />

        <div
          id="admin-settings-main"
          class="flex-1 flex flex-col min-w-0 bg-white dark:bg-zinc-900 overflow-auto"
        >
          {render_slot(@main)}
        </div>
      </div>
    </div>
    """
  end

  # --- sidebar_nav ----------------------------------------------------------

  @doc """
  Left rail listing the admin sub-sections. Vertical list (NOT icon
  strip like Activity Bar) because the sections are labeled.
  """
  attr(:active_section, :atom, required: true)

  def sidebar_nav(assigns) do
    assigns = assign(assigns, :items, sections())

    ~H"""
    <nav
      id="admin-settings-sidebar"
      phx-click-away={Phoenix.LiveView.JS.hide(to: "#admin-settings-sidebar")}
      class="hidden lg:flex lg:static fixed top-10 bottom-0 left-0 z-40 w-56 max-w-[80vw] border-r border-zinc-200 dark:border-zinc-800 bg-zinc-50 dark:bg-zinc-950 flex-col py-2 px-2 gap-px shrink-0 shadow-xl lg:shadow-none"
    >
      <div class="text-[10px] uppercase tracking-wide text-zinc-500 px-2 mb-1">
        Admin Settings
      </div>
      <a
        :for={item <- @items}
        href={item.path}
        class={[
          "flex items-center gap-2 px-2 py-1.5 text-xs rounded-md transition-colors",
          (item.key == @active_section &&
             "bg-white dark:bg-zinc-900 text-zinc-900 dark:text-zinc-100 font-medium shadow-sm border border-zinc-200 dark:border-zinc-800") ||
            "text-zinc-600 dark:text-zinc-400 hover:bg-zinc-100 dark:hover:bg-zinc-800 hover:text-zinc-900 dark:hover:text-zinc-100"
        ]}
        aria-current={(item.key == @active_section && "page") || nil}
      >
        <.icon name={item.icon} size="xs" />
        <span>{item.label}</span>
      </a>
    </nav>
    """
  end

  # --- sections / routing helpers ------------------------------------------

  @doc """
  The 5 admin sub-sections in display order. Each entry:

      %{key: atom, label: String.t(), icon: String.t(), path: String.t()}

  PR-M (Allen 2026-05-20): `:workspaces` inserted after `:overview` —
  the `/workspaces` and `/workspaces/:name` routes now render inside
  this drawer (workspace management is config, not workflow).
  """
  @spec sections() :: [%{key: atom(), label: String.t(), icon: String.t(), path: String.t()}]
  def sections do
    [
      %{key: :overview, label: "Overview", icon: "dashboard", path: "/admin"},
      %{key: :workspaces, label: "Workspaces", icon: "folder", path: "/workspaces"},
      %{key: :logs, label: "Logs & Audit", icon: "bug", path: "/admin/logs"},
      %{key: :registry, label: "Registry", icon: "users", path: "/admin/registry"},
      %{key: :snapshots, label: "Snapshots", icon: "folder", path: "/admin/snapshots"}
    ]
  end

  @doc """
  Compute the active sidebar section from the current path. Used as a
  fallback when the caller doesn't pass `active_section` explicitly.

  Examples:

      iex> section_for_path("/admin")
      :overview

      iex> section_for_path("/admin/logs")
      :logs

      iex> section_for_path("/admin/registry")
      :registry

      iex> section_for_path("/admin/snapshots")
      :snapshots

      iex> section_for_path("/workspaces")
      :workspaces

      iex> section_for_path("/workspaces/demo")
      :workspaces

      iex> section_for_path("/sessions")
      :overview
  """
  @spec section_for_path(String.t() | nil) :: atom()
  def section_for_path(path) when is_binary(path) do
    cond do
      String.starts_with?(path, "/admin/logs") -> :logs
      String.starts_with?(path, "/admin/registry") -> :registry
      String.starts_with?(path, "/admin/snapshots") -> :snapshots
      String.starts_with?(path, "/workspaces") -> :workspaces
      # /admin and any unknown path default to Overview (Allen's pivot
      # treats Overview as the "home" of the admin drawer).
      true -> :overview
    end
  end

  def section_for_path(_), do: :overview
end
