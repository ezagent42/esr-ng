defmodule EzagentDomainUi.AdminSettingsShellTest do
  @moduledoc """
  Phase 8c PR-F (Allen 2026-05-20) — admin settings drawer invariant tests.

  These assert the structural contract of the new "settings drawer"
  shell that replaces IdeShell for /admin/* routes: no Activity Bar,
  no status bar, sidebar nav for sub-sections, top bar with Back link.
  """
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias EzagentDomainUi.AdminSettingsShell

  describe "admin_settings_shell/1" do
    test "renders shell + topbar + sidebar + main" do
      assigns = %{
        current_entity_uri: "entity://user/admin",
        current_path: "/admin"
      }

      html =
        rendered_to_string(~H"""
        <AdminSettingsShell.admin_settings_shell
          current_entity_uri={@current_entity_uri}
          current_path={@current_path}
        >
          <:main>HELLO_MAIN_CONTENT</:main>
        </AdminSettingsShell.admin_settings_shell>
        """)

      assert html =~ ~s(id="admin-settings-shell")
      assert html =~ ~s(id="admin-settings-topbar")
      assert html =~ ~s(id="admin-settings-sidebar")
      assert html =~ ~s(id="admin-settings-main")
      assert html =~ "HELLO_MAIN_CONTENT"
      assert html =~ "Admin Settings"
      assert html =~ "Back to ezagent"
    end

    test "Back link defaults to /sessions" do
      assigns = %{current_entity_uri: "entity://user/admin", current_path: "/admin"}

      html =
        rendered_to_string(~H"""
        <AdminSettingsShell.admin_settings_shell
          current_entity_uri={@current_entity_uri}
          current_path={@current_path}
        >
          <:main>x</:main>
        </AdminSettingsShell.admin_settings_shell>
        """)

      assert html =~ ~s(href="/sessions")
    end

    test "Back link respects custom back_href" do
      assigns = %{
        current_entity_uri: "entity://user/admin",
        current_path: "/admin",
        back_href: "/workspaces/default"
      }

      html =
        rendered_to_string(~H"""
        <AdminSettingsShell.admin_settings_shell
          current_entity_uri={@current_entity_uri}
          current_path={@current_path}
          back_href={@back_href}
        >
          <:main>x</:main>
        </AdminSettingsShell.admin_settings_shell>
        """)

      assert html =~ ~s(href="/workspaces/default")
    end

    test "does NOT render Activity Bar or status bar" do
      assigns = %{current_entity_uri: "entity://user/admin", current_path: "/admin"}

      html =
        rendered_to_string(~H"""
        <AdminSettingsShell.admin_settings_shell
          current_entity_uri={@current_entity_uri}
          current_path={@current_path}
        >
          <:main>x</:main>
        </AdminSettingsShell.admin_settings_shell>
        """)

      # AdminSettingsShell is structurally NOT an IdeShell — no
      # 5-Activity icon strip, no bottom status bar.
      refute html =~ ~s(id="ide-shell")
      refute html =~ "agents"
      refute html =~ "bridges"
      refute html =~ ~s(aria-label="Sessions")
      refute html =~ ~s(aria-label="Workspaces")
    end

    test "sidebar lists all 4 sub-sections" do
      assigns = %{current_entity_uri: "entity://user/admin", current_path: "/admin"}

      html =
        rendered_to_string(~H"""
        <AdminSettingsShell.admin_settings_shell
          current_entity_uri={@current_entity_uri}
          current_path={@current_path}
        >
          <:main>x</:main>
        </AdminSettingsShell.admin_settings_shell>
        """)

      assert html =~ "Overview"
      assert html =~ "Logs &amp; Audit" or html =~ "Logs & Audit"
      assert html =~ "Registry"
      assert html =~ "Snapshots"
      # Each entry links to its /admin/* path.
      assert html =~ ~s(href="/admin")
      assert html =~ ~s(href="/admin/logs")
      assert html =~ ~s(href="/admin/registry")
      assert html =~ ~s(href="/admin/snapshots")
    end

    test "active_section explicit value highlights that sidebar item" do
      assigns = %{
        current_entity_uri: "entity://user/admin",
        current_path: "/admin",
        active_section: :registry
      }

      html =
        rendered_to_string(~H"""
        <AdminSettingsShell.admin_settings_shell
          current_entity_uri={@current_entity_uri}
          current_path={@current_path}
          active_section={@active_section}
        >
          <:main>x</:main>
        </AdminSettingsShell.admin_settings_shell>
        """)

      # The active item carries aria-current="page".
      assert html =~ ~s(aria-current="page")
    end

    test "active_section defaults to section_for_path(current_path)" do
      assigns = %{current_entity_uri: "entity://user/admin", current_path: "/admin/snapshots"}

      html =
        rendered_to_string(~H"""
        <AdminSettingsShell.admin_settings_shell
          current_entity_uri={@current_entity_uri}
          current_path={@current_path}
        >
          <:main>x</:main>
        </AdminSettingsShell.admin_settings_shell>
        """)

      assert html =~ ~s(aria-current="page")
    end
  end

  describe "section_for_path/1" do
    test "/admin → :overview" do
      assert AdminSettingsShell.section_for_path("/admin") == :overview
    end

    test "/admin/logs → :logs" do
      assert AdminSettingsShell.section_for_path("/admin/logs") == :logs
    end

    test "/admin/registry → :registry" do
      assert AdminSettingsShell.section_for_path("/admin/registry") == :registry
    end

    test "/admin/snapshots → :snapshots" do
      assert AdminSettingsShell.section_for_path("/admin/snapshots") == :snapshots
    end

    test "unknown path → :overview (fallback)" do
      assert AdminSettingsShell.section_for_path("/sessions") == :overview
      assert AdminSettingsShell.section_for_path("/anything") == :overview
    end

    test "nil → :overview" do
      assert AdminSettingsShell.section_for_path(nil) == :overview
    end
  end

  describe "sections/0" do
    test "returns 4 sub-sections in display order" do
      items = AdminSettingsShell.sections()
      assert length(items) == 4
      keys = Enum.map(items, & &1.key)
      assert keys == [:overview, :logs, :registry, :snapshots]
    end

    test "each section has key/label/icon/path" do
      for section <- AdminSettingsShell.sections() do
        assert is_atom(section.key)
        assert is_binary(section.label)
        assert is_binary(section.icon)
        assert is_binary(section.path)
        assert String.starts_with?(section.path, "/admin")
      end
    end
  end
end
