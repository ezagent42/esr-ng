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
      # Activity Bar
      assert html =~ "Sessions"
      assert html =~ "Workspaces"
      assert html =~ "Identities"
      assert html =~ "Routing"
      assert html =~ "Plugins"
      assert html =~ "Observability"
      assert html =~ "Settings"
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
    test "/admin → :sessions" do
      assert IdeShell.activity_for_path("/admin") == :sessions
    end

    test "/admin/workspaces → :workspaces" do
      assert IdeShell.activity_for_path("/admin/workspaces") == :workspaces
      assert IdeShell.activity_for_path("/admin/workspaces/demo") == :workspaces
    end

    test "/admin/entities → :identities" do
      assert IdeShell.activity_for_path("/admin/entities") == :identities
    end

    test "/admin/users + /admin/agents both → :identities (entity sub-types)" do
      assert IdeShell.activity_for_path("/admin/users") == :identities
      assert IdeShell.activity_for_path("/admin/users/foo/caps") == :identities
      assert IdeShell.activity_for_path("/admin/agents/foo/terminal") == :identities
    end

    test "/admin/routing → :routing" do
      assert IdeShell.activity_for_path("/admin/routing") == :routing
    end

    test "/admin/feishu/* + /admin/auto/* → :plugins" do
      assert IdeShell.activity_for_path("/admin/feishu/bindings") == :plugins
      assert IdeShell.activity_for_path("/admin/auto/user") == :plugins
    end

    test "/admin/observability + /admin/snapshots → :observability" do
      assert IdeShell.activity_for_path("/admin/observability") == :observability
      assert IdeShell.activity_for_path("/admin/snapshots") == :observability
    end

    test "/admin/settings → :settings" do
      assert IdeShell.activity_for_path("/admin/settings") == :settings
    end

    test "unknown path → :sessions (fallback)" do
      assert IdeShell.activity_for_path("/something-else") == :sessions
    end
  end

  describe "activity_items/0" do
    test "returns 7 items in the SPEC-defined order" do
      items = IdeShell.activity_items()
      assert length(items) == 7
      keys = Enum.map(items, & &1.key)
      assert keys == [:sessions, :workspaces, :identities, :routing, :plugins, :observability, :settings]
    end
  end

  describe "status_bar/1" do
    test "shows entity, workspace, agents, bridges, events, version" do
      assigns = %{
        current_entity_uri: "entity://user/admin",
        workspace_name: "default",
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
          workspace_name={@workspace_name}
          status={@status}
        />
        """)

      assert html =~ "entity://user/admin"
      assert html =~ "default"
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
