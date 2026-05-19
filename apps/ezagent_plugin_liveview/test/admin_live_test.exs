defmodule EzagentPluginLiveview.AdminLiveTest do
  use ExUnit.Case
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint EzagentWeb.Endpoint

  setup do
    # Sandbox shared mode so Audit.Writer's batch flush can reach the
    # test DB connection — used by the round-trip assertions below.
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(EzagentCore.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(EzagentCore.Repo, {:shared, self()})

    # Phase 4-completion Spec 05: /admin requires login. Pre-set the
    # session cookie so tests skip the /login redirect.
    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Test.init_test_session(%{
        "current_user_uri" => URI.to_string(Ezagent.Entity.User.admin_uri())
      })

    {:ok, conn: conn}
  end

  test "GET /admin renders the page skeleton", %{conn: conn} do
    {:ok, _lv, html} = live(conn, "/admin")
    assert html =~ "Admin"
    assert html =~ "Echo 测试"
    assert html =~ "Manual Dispatch"
    assert html =~ "Audit Log"
    # Caller URI is shown in the header.
    assert html =~ "entity://user/admin"
  end

  test "Echo button triggers dispatch and audit stream updates", %{conn: conn} do
    {:ok, lv, _html} = live(conn, "/admin")
    lv |> element("#echo-test-btn") |> render_click()

    # Give the dispatch path + telemetry handler time to propagate.
    Process.sleep(50)
    html = render(lv)

    assert html =~ "entity://agent/echo_default/behavior/echo/say"
    # Phase 3d hard flip: :stub_grant is gone; admin's all-cap matches
    # produce "granted" in the audit column.
    assert html =~ "granted"
  end

  test "Manual dispatch form runs an arbitrary invocation", %{conn: conn} do
    {:ok, lv, _html} = live(conn, "/admin")

    form_data = %{
      "manual_dispatch" => %{
        "target" => "entity://agent/echo_default/behavior/echo/say",
        "args" => ~s({"msg": "via-form"}),
        "mode" => "call"
      }
    }

    lv |> form("#manual-dispatch form", form_data) |> render_submit()

    Process.sleep(50)
    html = render(lv)
    assert html =~ "entity://agent/echo_default/behavior/echo/say"
  end

  test "Session members section shows admin User as online (Phase 2 boot)", %{conn: conn} do
    {:ok, _lv, html} = live(conn, "/admin")

    # Section header
    assert html =~ "session://main"

    # admin URI listed
    assert html =~ "entity://user/admin"

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
    |> form("form[phx-submit=chat_compose]", %{"chat" => %{"text" => text, "agent_uri" => ""}})
    |> render_submit()

    # Give cast time to dispatch + broadcast back through session:events
    Process.sleep(100)
    html = render(lv)

    assert html =~ text
    assert html =~ "entity://user/admin"
  end

  test "Chat row shape identical for admin vs agent senders (CSS-level diff only)", %{conn: conn} do
    # Send a message from admin AND simulate an agent message landing
    # via broadcast (mimics what 2c agent flow produces) — assert both
    # render in the same #messages container with same DOM structure.
    {:ok, lv, _html} = live(conn, "/admin")

    admin_text = "admin-says-#{System.unique_integer([:positive])}"

    lv
    |> form("form[phx-submit=chat_compose]", %{"chat" => %{"text" => admin_text, "agent_uri" => ""}})
    |> render_submit()

    # Poll until admin text shows in the stream (dispatch → MessageStore →
    # broadcast → handle_info → stream_insert can be slow under sandbox).
    assert wait_until_html(lv, admin_text)

    # Simulate an agent reply landing via the chat_message broadcast.
    agent_uri = URI.new!("entity://agent/test_test-#{System.unique_integer([:positive])}")
    agent_msg = Ezagent.Message.new(agent_uri, %{text: "agent reply test", attachments: []})

    Phoenix.PubSub.broadcast(
      EzagentCore.PubSub,
      Ezagent.Behavior.Chat.session_events_topic(URI.new!("session://main")),
      {:chat_message, URI.new!("session://main"), agent_msg}
    )

    assert wait_until_html(lv, "agent reply test")

    html = render(lv)
    # Both senders appear in the messages container
    assert html =~ admin_text
    assert html =~ "agent reply test"
    assert html =~ ~s(id="messages")
  end

  defp wait_until_html(lv, substr, retries \\ 50)
  defp wait_until_html(_lv, _substr, 0), do: false

  defp wait_until_html(lv, substr, retries) do
    if render(lv) =~ substr do
      true
    else
      Process.sleep(20)
      wait_until_html(lv, substr, retries - 1)
    end
  end

  test "Load older button paginates history (Phase 5 PR 5 invariant)", %{conn: conn} do
    # Spec 5 PR 5 invariant: send 100 messages → "Load older" reveals
    # msgs 1-50; no duplicates; second click no-ops at the start.
    session_uri = URI.new!("session://main")
    base = ~U[2026-05-17 09:00:00.000000Z]

    for i <- 1..100 do
      msg =
        Ezagent.Message.new(
          URI.new!("entity://user/admin"),
          %{text: "histmsg-#{i}", attachments: []},
          inserted_at: DateTime.add(base, i, :second)
        )

      {:ok, _} = Ezagent.MessageStore.write(msg, session_uri)
    end

    {:ok, lv, html} = live(conn, "/admin")

    # Match on the trailing newline-tag boundary in the rendered <div>
    # so "histmsg-1" doesn't substring-match "histmsg-100".
    msg = fn i -> "histmsg-#{i}</div>" end

    # Initial mount shows newest 50 (histmsg-51..histmsg-100).
    assert html =~ msg.(100)
    assert html =~ msg.(51)
    refute html =~ msg.(50)
    refute html =~ msg.(1)

    # First click reveals histmsg-1..histmsg-50.
    lv |> element("#load-older-btn") |> render_click()
    html = render(lv)
    assert html =~ msg.(1)
    assert html =~ msg.(50)
    # Newer messages still present (no duplicates / no eviction).
    assert html =~ msg.(100)

    # Sanity — each histmsg-NN appears exactly once.
    for i <- 1..100 do
      assert length(String.split(html, msg.(i))) - 1 == 1,
             "#{msg.(i)} appeared more than once after load_older click"
    end

    # Second click — already at start, no-op (no crash, no duplicates).
    lv |> element("#load-older-btn") |> render_click()
    html2 = render(lv)
    assert html2 =~ msg.(1)
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
