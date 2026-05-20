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
        current_entity_uri: "entity://user/admin",
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
      # Activity Bar — 5 items per Phase 8c PR-F (Allen 2026-05-20).
      # Dashboard removed: /admin is now a settings drawer rendered by
      # AdminSettingsShell, not a peer Activity.
      assert html =~ "Sessions"
      assert html =~ "Workspaces"
      assert html =~ "Identities"
      assert html =~ "Routing"
      assert html =~ "Plugins"
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
        current_entity_uri: "entity://user/admin",
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
        current_entity_uri: "entity://user/admin",
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

    test "Phase 8c PR-F — avatar dropdown gains Admin link when is_admin?=true" do
      assigns = %{
        current_entity_uri: "entity://user/admin",
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
        current_entity_uri: "entity://user/alice",
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

    test "/workspaces → :workspaces" do
      assert IdeShell.activity_for_path("/workspaces") == :workspaces
      assert IdeShell.activity_for_path("/workspaces/demo") == :workspaces
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
    test "returns 5 items in the SPEC-defined order (Phase 8c PR-F)" do
      items = IdeShell.activity_items()
      assert length(items) == 5
      keys = Enum.map(items, & &1.key)
      assert keys == [:sessions, :workspaces, :identities, :routing, :plugins]
      # Dashboard explicitly NOT in the list — it's a settings drawer
      # (`EzagentDomainUi.AdminSettingsShell`) opened from the avatar
      # dropdown, not a peer Activity Bar item.
      refute :dashboard in keys
    end
  end

  describe "status_bar/1" do
    test "shows entity, session, agents, bridges, events, version" do
      # Phase 8 polish (Allen 2026-05-20) — workspace label removed
      # from status bar (workspace context is shown in the URL/route,
      # not the bottom bar).
      assigns = %{
        current_entity_uri: "entity://user/admin",
        status: %{
          session_uri: "session://main",
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

      assert html =~ "entity://user/admin"
      assert html =~ "session://main"
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
            key: "session://main",
            label: "session://main",
            icon: "message-square",
            group: "session"
          }
        ]
      }

      html =
        rendered_to_string(~H"""
        <IdeShell.command_palette open={@open} query={@query} results={@results} />
        """)

      assert html =~ "session://main"
      refute html =~ "没有结果"
    end
  end
end
