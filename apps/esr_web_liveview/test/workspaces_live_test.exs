defmodule EsrWebLiveview.WorkspacesLiveTest do
  use ExUnit.Case
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint EsrWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(EsrCore.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(EsrCore.Repo, {:shared, self()})
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  test "GET /admin/workspaces shows empty state when no workspaces", %{conn: conn} do
    {:ok, _lv, html} = live(conn, "/admin/workspaces")
    assert html =~ "Workspaces"
    assert html =~ "+ New Workspace"
    assert html =~ "No workspaces yet"
  end

  test "create form spawns + persists a workspace", %{conn: conn} do
    {:ok, lv, _html} = live(conn, "/admin/workspaces")

    name = "lv-create-#{System.unique_integer([:positive])}"

    lv
    |> form("#create-workspace form", new_workspace: %{name: name})
    |> render_submit()

    html = render(lv)
    assert html =~ name
    assert html =~ "workspace://#{name}"

    # And it's persisted (Store) + live (KindRegistry)
    assert %{name: ^name} = Esr.Workspace.Store.get_by_name(name)
    assert {:ok, _pid} = Esr.KindRegistry.lookup(Esr.Entity.Workspace.uri_for(name))
  end

  test "detail page for non-existent workspace shows 'not found'", %{conn: conn} do
    {:ok, _lv, html} = live(conn, "/admin/workspaces/never-existed-#{System.unique_integer([:positive])}")
    assert html =~ "Workspace not found"
  end

  test "detail page shows existing workspace + members section", %{conn: conn} do
    name = "lv-detail-#{System.unique_integer([:positive])}"
    {:ok, _} = Esr.Workspace.create(name)

    {:ok, _lv, html} = live(conn, "/admin/workspaces/#{name}")
    assert html =~ "Workspace: <code>#{name}</code>"
    assert html =~ "Members (0)"
    assert html =~ "No members"
  end

  test "add_member from detail page persists + appears in list", %{conn: conn} do
    name = "lv-add-#{System.unique_integer([:positive])}"
    {:ok, _} = Esr.Workspace.create(name)

    {:ok, lv, _html} = live(conn, "/admin/workspaces/#{name}")

    lv
    |> form("#members form", add_member: %{member_uri: "agent://test-add"})
    |> render_submit()

    html = render(lv)
    assert html =~ "agent://test-add"
    assert html =~ "Members (1)"
  end
end
