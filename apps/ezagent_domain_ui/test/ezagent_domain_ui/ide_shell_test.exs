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
        current_path: "/admin",
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
      # Activity Bar — 6 items per Phase 8 polish (Allen 2026-05-20)
      assert html =~ "Sessions"
      assert html =~ "Workspaces"
      assert html =~ "Identities"
      assert html =~ "Routing"
      assert html =~ "Plugins"
      assert html =~ "Dashboard"
      # Phase 8 polish (Allen 2026-05-20): Settings moved from
      # Activity Bar into the avatar dropdown, so its label appears
      # in HTML but NOT as an Activity Bar tile. We assert it's not
      # in the activity bar specifically.
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

    test "/admin → :dashboard" do
      assert IdeShell.activity_for_path("/admin") == :dashboard
      assert IdeShell.activity_for_path("/admin/logs") == :dashboard
      assert IdeShell.activity_for_path("/admin/registry") == :dashboard
      assert IdeShell.activity_for_path("/admin/snapshots") == :dashboard
    end

    test "unknown path → :sessions (fallback)" do
      assert IdeShell.activity_for_path("/something-else") == :sessions
    end
  end

  describe "activity_items/0" do
    test "returns 6 items in the SPEC-defined order (post-polish)" do
      items = IdeShell.activity_items()
      assert length(items) == 6
      keys = Enum.map(items, & &1.key)
      assert keys == [:sessions, :workspaces, :identities, :routing, :plugins, :dashboard]
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
          %{key: "session://main", label: "session://main", icon: "message-square", group: "session"}
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
