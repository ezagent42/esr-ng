defmodule EzagentDomainUi.IdeShellTest do
  @moduledoc """
  Phase 8 — IDE Shell layout + Activity Bar + Top Command Bar + Status
  Bar invariant tests. These don't validate visual details; they assert
  the structural IA contract per spec §6.
  """
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias EzagentDomainUi.IdeShell

  describe "ide_shell/1" do
    test "renders the 6 layout regions" do
      assigns = %{
        current_entity_uri: "entity://user/system/admin",
        current_path: "/sessions",
        status: %{agents_alive: 0, bridges: 0, debug_events: 0, version: "test"}
      }

      html =
        rendered_to_string(~H"""
        <IdeShell.ide_shell
          current_entity_uri={@current_entity_uri}
          current_path={@current_path}
          status={@status}
        >
          <:resource_panel>panel</:resource_panel>
          <:main_window>main</:main_window>
        </IdeShell.ide_shell>
        """)

      assert html =~ ~r/id="ide-shell"/
      # Activity Bar — 4 items per Phase 8c PR-L (Allen 2026-05-20).
      # Dashboard removed in PR-F (admin became a settings drawer);
      # Workspaces removed in PR-L (folded into the top-left
      # `ezagent / <workspace>` dropdown — workspace is a context
      # container, not a feature surface).
      assert html =~ "Sessions"
      assert html =~ "Identities"
      assert html =~ "Routing"
      assert html =~ "Plugins"
      # Workspaces no longer an Activity Bar tile (the WorkspacesLive
      # page itself still renders — reachable via the top-left
      # "Manage workspaces..." dropdown link).
      refute html =~ ~s(aria-label="Workspaces")
      refute html =~ ~s(aria-label="Dashboard")
      # Phase 8 polish (Allen 2026-05-20): Settings moved from
      # Activity Bar into the avatar dropdown, so its label appears
      # in HTML (theme picker, Admin link icon, etc.) but NOT as an
      # Activity Bar tile.
      refute html =~ ~s(aria-label="Settings")
      refute html =~ ~s(aria-label="Observability")
      # Top Command Bar
      assert html =~ "ezagent"
      assert html =~ "⌘K"
      # Resource Panel slot rendered
      assert html =~ "panel"
      # Main Window slot rendered
      assert html =~ "main"
      # Status Bar
      assert html =~ "agents"
      assert html =~ "bridges"
      assert html =~ "events"
    end

    test "Phase 8c PR-F — top-left shows `ezagent / <workspace_name>` when given" do
      assigns = %{
        current_entity_uri: "entity://user/system/admin",
        current_path: "/sessions",
        status: %{},
        workspace_name: "default"
      }

      html =
        rendered_to_string(~H"""
        <IdeShell.ide_shell
          current_entity_uri={@current_entity_uri}
          current_path={@current_path}
          status={@status}
          workspace_name={@workspace_name}
        >
          <:main_window>main</:main_window>
        </IdeShell.ide_shell>
        """)

      assert html =~ "ezagent"
      assert html =~ "default"
    end

    test "Phase 8c PR-F — top-left shows bare `ezagent` when workspace_name is nil" do
      assigns = %{
        current_entity_uri: "entity://user/system/admin",
        current_path: "/sessions",
        status: %{}
      }

      html =
        rendered_to_string(~H"""
        <IdeShell.ide_shell
          current_entity_uri={@current_entity_uri}
          current_path={@current_path}
          status={@status}
        >
          <:main_window>main</:main_window>
        </IdeShell.ide_shell>
        """)

      assert html =~ "ezagent"
    end

    test "Phase 8c PR-L — top-left becomes a dropdown when workspaces list is non-empty" do
      assigns = %{
        current_entity_uri: "entity://user/system/admin",
        current_path: "/sessions",
        status: %{},
        workspace_name: "default",
        workspaces: [
          %{name: "default", uri: "workspace://default"},
          %{name: "demo", uri: "workspace://demo"}
        ]
      }

      html =
        rendered_to_string(~H"""
        <IdeShell.ide_shell
          current_entity_uri={@current_entity_uri}
          current_path={@current_path}
          status={@status}
          workspace_name={@workspace_name}
          workspaces={@workspaces}
        >
          <:main_window>main</:main_window>
        </IdeShell.ide_shell>
        """)

      # Dropdown structure
      assert html =~ ~s(id="workspace-menu")
      assert html =~ ~s(aria-label="Switch workspace")
      # WORKSPACES caption (case-insensitive — Tailwind uppercase class
      # renders the source text lowercase)
      assert html =~ "Workspaces"
      # Both workspaces appear in the list
      assert html =~ "default"
      assert html =~ "demo"
      # Current marker on the active workspace
      assert html =~ "current"
      # Phase 9 PR-5 (SPEC v3 §6.4 amended): non-current workspace
      # POSTs to /workspaces/switch (logout + re-auth flow), not a
      # bare link to /workspaces/<name>. The hidden `workspace` field
      # carries the target so the controller can route the user.
      assert html =~ ~s(action="/workspaces/switch")
      assert html =~ ~s(name="workspace" value="demo")
      # Manage link still points to /workspaces (separate "Manage
      # workspaces..." entry at the bottom of the dropdown).
      assert html =~ ~s(href="/workspaces")
      assert html =~ "Manage workspaces..."
    end

    test "Phase 8c PR-L — empty workspaces list keeps plain text label (no dropdown)" do
      assigns = %{
        current_entity_uri: "entity://user/system/admin",
        current_path: "/sessions",
        status: %{},
        workspace_name: "default",
        workspaces: []
      }

      html =
        rendered_to_string(~H"""
        <IdeShell.ide_shell
          current_entity_uri={@current_entity_uri}
          current_path={@current_path}
          status={@status}
          workspace_name={@workspace_name}
          workspaces={@workspaces}
        >
          <:main_window>main</:main_window>
        </IdeShell.ide_shell>
        """)

      # Plain text still rendered
      assert html =~ "ezagent"
      assert html =~ "default"
      # No dropdown apparatus
      refute html =~ ~s(id="workspace-menu")
      refute html =~ ~s(aria-label="Switch workspace")
    end

    test "Phase 8c PR-F — avatar dropdown gains Admin link when is_admin?=true" do
      assigns = %{
        current_entity_uri: "entity://user/system/admin",
        current_path: "/sessions",
        status: %{},
        is_admin?: true
      }

      html =
        rendered_to_string(~H"""
        <IdeShell.ide_shell
          current_entity_uri={@current_entity_uri}
          current_path={@current_path}
          status={@status}
          is_admin?={@is_admin?}
        >
          <:main_window>main</:main_window>
        </IdeShell.ide_shell>
        """)

      assert html =~ ~s(href="/admin")
      assert html =~ "Admin"
    end

    test "Phase 8c PR-F — avatar dropdown hides Admin link when is_admin?=false" do
      assigns = %{
        current_entity_uri: "entity://user/default/alice",
        current_path: "/sessions",
        status: %{},
        is_admin?: false
      }

      html =
        rendered_to_string(~H"""
        <IdeShell.ide_shell
          current_entity_uri={@current_entity_uri}
          current_path={@current_path}
          status={@status}
          is_admin?={@is_admin?}
        >
          <:main_window>main</:main_window>
        </IdeShell.ide_shell>
        """)

      # /admin link in the dropdown is hidden. Note: status bar may
      # still link to /admin/logs (events link), so we use a more
      # specific assertion: the dropdown Admin link has the icon+text
      # combination, which won't appear elsewhere on the page.
      refute html =~ ~r/<a[^>]*href="\/admin"[^>]*>\s*<span[^>]*aria-label="settings"/
    end
  end

  describe "activity_for_path/1" do
    # Phase 8 polish (Allen 2026-05-20) — IA refactor: /admin/X → /X promoted
    # to top-level Activity Bar destinations. /admin is now the management
    # dashboard (with /admin/logs + /admin/registry + /admin/snapshots as
    # sub-pages).
    test "/sessions → :sessions" do
      assert IdeShell.activity_for_path("/sessions") == :sessions
      assert IdeShell.activity_for_path("/sessions/main") == :sessions
    end

    test "/workspaces → nil (Phase 8c PR-L: workspaces folded into top-left dropdown)" do
      # PR-L removed the Workspaces Activity Bar tile. WorkspacesLive
      # still renders (reachable via the top-left "Manage workspaces..."
      # dropdown link), but no Activity should highlight while it's open.
      assert IdeShell.activity_for_path("/workspaces") == nil
      assert IdeShell.activity_for_path("/workspaces/demo") == nil
    end

    test "/identities → :identities" do
      assert IdeShell.activity_for_path("/identities") == :identities
      assert IdeShell.activity_for_path("/identities/users/foo/caps") == :identities
      assert IdeShell.activity_for_path("/identities/agents/foo/terminal") == :identities
    end

    test "/routing → :routing" do
      assert IdeShell.activity_for_path("/routing") == :routing
    end

    test "/plugins → :plugins" do
      assert IdeShell.activity_for_path("/plugins") == :plugins
      assert IdeShell.activity_for_path("/plugins/feishu/bindings") == :plugins
    end

    test "/admin → nil (Phase 8c PR-F: admin is a settings drawer, not an Activity)" do
      # The drawer (AdminSettingsShell) doesn't even render the
      # Activity Bar, but activity_for_path/1 still returns nil so
      # any caller that happens to evaluate it on an /admin path
      # gets a sane non-highlighted result.
      assert IdeShell.activity_for_path("/admin") == nil
      assert IdeShell.activity_for_path("/admin/logs") == nil
      assert IdeShell.activity_for_path("/admin/registry") == nil
      assert IdeShell.activity_for_path("/admin/snapshots") == nil
    end

    test "unknown path → :sessions (fallback)" do
      assert IdeShell.activity_for_path("/something-else") == :sessions
    end
  end

  describe "activity_items/0" do
    test "returns 4 items in the SPEC-defined order (Phase 8c PR-L)" do
      items = IdeShell.activity_items()
      assert length(items) == 4
      keys = Enum.map(items, & &1.key)
      assert keys == [:sessions, :identities, :routing, :plugins]
      # Dashboard explicitly NOT in the list — it's a settings drawer
      # (`EzagentDomainUi.AdminSettingsShell`) opened from the avatar
      # dropdown, not a peer Activity Bar item.
      refute :dashboard in keys
      # Workspaces explicitly NOT in the list (PR-L) — workspace is a
      # context container, folded into the top-left `ezagent /
      # <workspace>` dropdown. /workspaces management page still exists,
      # reached via "Manage workspaces..." link in that dropdown.
      refute :workspaces in keys
    end
  end

  describe "status_bar/1" do
    test "shows entity, session, agents, bridges, events, version" do
      # Phase 8 polish (Allen 2026-05-20) — workspace label removed
      # from status bar (workspace context is shown in the URL/route,
      # not the bottom bar).
      assigns = %{
        current_entity_uri: "entity://user/system/admin",
        status: %{
          session_uri: "session://default/default/main",
          agents_alive: 3,
          bridges: 1,
          debug_events: 5,
          version: "0.42"
        }
      }

      html =
        rendered_to_string(~H"""
        <IdeShell.status_bar
          current_entity_uri={@current_entity_uri}
          status={@status}
        />
        """)

      assert html =~ "entity://user/system/admin"
      assert html =~ "session://default/default/main"
      assert html =~ "3 agents"
      assert html =~ "1 bridges"
      assert html =~ "5 events"
      assert html =~ "v0.42"
    end
  end

  describe "editor_tabs/1" do
    test "renders tab labels + close buttons" do
      assigns = %{
        items: [{:session_main, "main"}, {:terminal_x, "cc_demo"}],
        selected: :session_main
      }

      html =
        rendered_to_string(~H"""
        <IdeShell.editor_tabs items={@items} selected={@selected} />
        """)

      assert html =~ "main"
      assert html =~ "cc_demo"
      # Close button per tab
      assert html =~ ~s(phx-value-key=":session_main")
      assert html =~ ~s(phx-value-key=":terminal_x")
    end
  end

  describe "command_palette/1" do
    test "hidden by default" do
      assigns = %{open: false, query: "", results: []}

      html =
        rendered_to_string(~H"""
        <IdeShell.command_palette open={@open} query={@query} results={@results} />
        """)

      # Container has the "hidden" class when open=false
      assert html =~ "hidden"
    end

    test "renders results when open" do
      assigns = %{
        open: true,
        query: "ses",
        results: [
          %{
            key: "session://default/default/main",
            label: "session://default/default/main",
            icon: "message-square",
            group: "session"
          }
        ]
      }

      html =
        rendered_to_string(~H"""
        <IdeShell.command_palette open={@open} query={@query} results={@results} />
        """)

      assert html =~ "session://default/default/main"
      refute html =~ "没有结果"
    end
  end
end
