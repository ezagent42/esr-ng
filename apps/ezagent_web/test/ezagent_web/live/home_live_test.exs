defmodule EzagentWeb.HomeLiveTest do
  use EzagentWeb.ConnCase

  import Phoenix.LiveViewTest

  test "GET / unauthenticated redirects to /login", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/login"}}} = live(conn, ~p"/")
  end

  test "GET / with session redirects to /sessions (Phase 8 polish)", %{conn: conn} do
    conn =
      conn
      |> Plug.Test.init_test_session(%{
        "current_entity_uri" => "entity://user/admin"
      })

    assert {:error, {:live_redirect, %{to: "/sessions"}}} = live(conn, ~p"/")
  end
end
