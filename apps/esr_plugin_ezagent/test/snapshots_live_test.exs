defmodule EsrPluginEzagent.SnapshotsLiveTest do
  use ExUnit.Case
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint EsrWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(EsrCore.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(EsrCore.Repo, {:shared, self()})

    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Test.init_test_session(%{
        "current_user_uri" => URI.to_string(Esr.Entity.User.admin_uri())
      })

    {:ok, conn: conn}
  end

  test "GET /admin/snapshots renders header", %{conn: conn} do
    {:ok, _lv, html} = live(conn, "/admin/snapshots")
    assert html =~ "Snapshots"
  end

  test "snapshot list shows persisted rows", %{conn: conn} do
    uri = URI.parse("user://snap-lv-#{System.unique_integer([:positive])}")
    :ok = Esr.Kind.Snapshot.save_now(uri, Esr.Entity.User, %{identity: %{caps: MapSet.new()}})

    {:ok, _lv, html} = live(conn, "/admin/snapshots")
    assert html =~ URI.to_string(uri)
  end

  test "clear deletes the snapshot row", %{conn: conn} do
    uri = URI.parse("user://snap-clear-#{System.unique_integer([:positive])}")
    uri_str = URI.to_string(uri)
    :ok = Esr.Kind.Snapshot.save_now(uri, Esr.Entity.User, %{identity: %{caps: MapSet.new()}})
    assert %{} = Esr.Ecto.KindSnapshot.get(uri_str)

    {:ok, lv, _html} = live(conn, "/admin/snapshots")

    lv
    |> element("button[phx-click='clear'][phx-value-uri='#{uri_str}']")
    |> render_click()

    assert nil == Esr.Ecto.KindSnapshot.get(uri_str)
  end
end
