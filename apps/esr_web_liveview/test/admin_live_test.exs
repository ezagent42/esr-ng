defmodule EsrWebLiveview.AdminLiveTest do
  use ExUnit.Case
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint EsrWeb.Endpoint

  setup do
    # Sandbox shared mode so Audit.Writer's batch flush can reach the
    # test DB connection — used by the round-trip assertions below.
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(EsrCore.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(EsrCore.Repo, {:shared, self()})

    conn = Phoenix.ConnTest.build_conn()
    {:ok, conn: conn}
  end

  test "GET /admin renders the page skeleton", %{conn: conn} do
    {:ok, _lv, html} = live(conn, "/admin")
    assert html =~ "Admin"
    assert html =~ "Echo 测试"
    assert html =~ "Manual Dispatch"
    assert html =~ "Audit Log"
    # Caller URI is shown in the header.
    assert html =~ "user://admin"
  end

  test "Echo button triggers dispatch and audit stream updates", %{conn: conn} do
    {:ok, lv, _html} = live(conn, "/admin")
    lv |> element("#echo-test-btn") |> render_click()

    # Give the dispatch path + telemetry handler time to propagate.
    Process.sleep(50)
    html = render(lv)

    assert html =~ "agent://echo/behavior/echo/say"
    assert html =~ "stub_grant"
  end

  test "Manual dispatch form runs an arbitrary invocation", %{conn: conn} do
    {:ok, lv, _html} = live(conn, "/admin")

    form_data = %{
      "manual_dispatch" => %{
        "target" => "agent://echo/behavior/echo/say",
        "args" => ~s({"msg": "via-form"}),
        "mode" => "call"
      }
    }

    lv |> form("#manual-dispatch form", form_data) |> render_submit()

    Process.sleep(50)
    html = render(lv)
    assert html =~ "agent://echo/behavior/echo/say"
  end

  test "Session members section shows admin User as online (Phase 2 boot)", %{conn: conn} do
    {:ok, _lv, html} = live(conn, "/admin")

    # Section header
    assert html =~ "session://main"

    # admin URI listed
    assert html =~ "user://admin"

    # admin is online (boot post-spawn dispatched chat/join)
    assert html =~ "online"

    # The members table id is rendered (not the empty-state placeholder)
    assert html =~ ~s(id="session-members-table")
    refute html =~ ~s(id="session-members-empty")
  end

  test "Manual dispatch with invalid URI shows error message", %{conn: conn} do
    {:ok, lv, _html} = live(conn, "/admin")

    form_data = %{
      "manual_dispatch" => %{
        "target" => "no-scheme",
        "args" => "",
        "mode" => "call"
      }
    }

    lv |> form("#manual-dispatch form", form_data) |> render_submit()
    html = render(lv)
    assert html =~ "target must include a scheme"
  end
end
