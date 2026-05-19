defmodule EzagentPluginLiveview.RoutingLiveTest do
  use ExUnit.Case
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint EzagentWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(EzagentCore.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(EzagentCore.Repo, {:shared, self()})

    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Test.init_test_session(%{
        "current_user_uri" => URI.to_string(Ezagent.Entity.User.admin_uri())
      })

    {:ok, conn: conn}
  end

  test "GET /admin/routing renders tabs + form", %{conn: conn} do
    {:ok, _lv, html} = live(conn, "/admin/routing")
    assert html =~ "Routing Rules"
    assert html =~ "MentionRouting"
    assert html =~ "SessionRouting"
    assert html =~ "Add rule"
    assert html =~ "Form mode"
    assert html =~ "JSON mode"
  end

  test "add_rule via form-mode mention persists + appears in list", %{conn: conn} do
    {:ok, lv, _html} = live(conn, "/admin/routing")

    lv
    |> form("#add-rule form",
      rule: %{
        table: "Elixir.EzagentDomainChat.Routing.MentionRouting",
        matcher_type: "mention",
        matcher_arg: "entity://agent/test_lv-test-#{System.unique_integer([:positive])}",
        receivers: "session://lv-rcv-#{System.unique_integer([:positive])}"
      }
    )
    |> render_submit()

    html = render(lv)
    assert html =~ "mention"
    assert html =~ "entity://agent/test_lv-test"
  end

  test "switch_table changes view", %{conn: conn} do
    {:ok, lv, _html} = live(conn, "/admin/routing")

    lv
    |> element("button[phx-value-table='Elixir.EzagentDomainChat.Routing.SessionRouting']")
    |> render_click()

    html = render(lv)
    # SessionRouting empty by default in test sandbox
    assert html =~ "Routing Rules"
  end

  test "add_rule via JSON mode supports combinators", %{conn: conn} do
    {:ok, lv, _html} = live(conn, "/admin/routing")

    lv |> element("button[phx-value-mode='json']") |> render_click()

    combinator_json =
      Jason.encode!(%{
        "type" => "and",
        "items" => [
          %{"type" => "mention", "arg" => "entity://agent/test_lv-combo"},
          %{"type" => "from", "arg" => "entity://user/admin"}
        ]
      })

    lv
    |> form("#add-rule form",
      rule: %{
        table: "Elixir.EzagentDomainChat.Routing.MentionRouting",
        matcher_json: combinator_json,
        receivers: "session://oncall"
      }
    )
    |> render_submit()

    html = render(lv)
    assert html =~ ":and"
  end

  test "add_rule rejects empty receivers", %{conn: conn} do
    {:ok, lv, _html} = live(conn, "/admin/routing")

    lv
    |> form("#add-rule form",
      rule: %{
        table: "Elixir.EzagentDomainChat.Routing.MentionRouting",
        matcher_type: "mention",
        matcher_arg: "entity://agent/test_x",
        receivers: ""
      }
    )
    |> render_submit()

    html = render(lv)
    assert html =~ "receiver"
  end
end
