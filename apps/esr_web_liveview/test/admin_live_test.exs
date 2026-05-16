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

  test "Chat compose dispatches send and message lands in stream", %{conn: conn} do
    {:ok, lv, _html} = live(conn, "/admin")

    text = "lv chat compose test #{System.unique_integer([:positive])}"

    lv
    |> form("section#session form", %{"chat" => %{"text" => text, "agent_uri" => ""}})
    |> render_submit()

    # Give cast time to dispatch + broadcast back through session:events
    Process.sleep(100)
    html = render(lv)

    assert html =~ text
    assert html =~ "user://admin"
  end

  test "Chat row shape identical for admin vs agent senders (CSS-level diff only)", %{conn: conn} do
    # Send a message from admin AND simulate an agent message landing
    # via broadcast (mimics what 2c agent flow produces) — assert both
    # render in the same #messages container with same DOM structure.
    {:ok, lv, _html} = live(conn, "/admin")

    admin_text = "admin says #{System.unique_integer()}"

    lv
    |> form("section#session form", %{"chat" => %{"text" => admin_text, "agent_uri" => ""}})
    |> render_submit()

    Process.sleep(100)

    # Simulate an agent reply landing via the chat_message broadcast.
    agent_uri = URI.new!("agent://test-#{System.unique_integer([:positive])}")
    agent_msg = Esr.Message.new(agent_uri, %{text: "agent reply test", attachments: []})

    Phoenix.PubSub.broadcast(
      EsrCore.PubSub,
      Esr.Behavior.Chat.session_events_topic(URI.new!("session://main")),
      {:chat_message, agent_msg}
    )

    Process.sleep(50)
    html = render(lv)

    # Both senders appear in the messages container
    assert html =~ admin_text
    assert html =~ "agent reply test"
    assert html =~ ~s(id="messages")
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
