defmodule EsrPluginEzagent.AutoDeriveLiveTest do
  @moduledoc """
  Phase 6 PR 10 — auto-derive LV smoke test.

  Validates the page mounts for any registered Kind without
  hand-written per-Kind code.
  """
  use ExUnit.Case, async: false
  import Plug.Conn
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint EsrWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(EsrCore.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(EsrCore.Repo, {:shared, self()})

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{
        "current_user_uri" => URI.to_string(Esr.Entity.User.admin_uri())
      })

    {:ok, conn: conn}
  end

  test "/admin/auto/session mounts + renders title", %{conn: conn} do
    {:ok, _lv, html} = live(conn, "/admin/auto/session")

    assert html =~ "Auto-derived: session"
    assert html =~ "live instance(s)"
  end

  test "/admin/auto/user mounts (admin user is live)", %{conn: conn} do
    {:ok, _lv, html} = live(conn, "/admin/auto/user")

    assert html =~ "Auto-derived: user"
  end

  test "/admin/auto/<unknown> mounts to empty list", %{conn: conn} do
    {:ok, _lv, html} = live(conn, "/admin/auto/nonexistent_kind")
    assert html =~ "No live instances"
  end
end
