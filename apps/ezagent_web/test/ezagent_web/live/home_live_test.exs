defmodule EzagentWeb.HomeLiveTest do
  use EzagentWeb.ConnCase

  import Phoenix.LiveViewTest

  test "GET / mounts the Phase 0 placeholder LiveView", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/")
    assert html =~ "ESR v0.4 — phase 0 complete"
  end
end
