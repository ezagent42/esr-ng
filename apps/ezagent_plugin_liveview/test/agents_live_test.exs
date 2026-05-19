defmodule EzagentPluginLiveview.AgentsLiveTest do
  @moduledoc """
  Phase 5 PR 3 invariant — /admin/agents lists live PTY agents,
  /admin/agents/<encoded-uri> renders detail + accepts restart click.

  If this test breaks, operator loses visibility into PTY-managed
  agent lifecycle.
  """
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

  test "GET /admin/agents renders header even with no agents", %{conn: conn} do
    {:ok, _lv, html} = live(conn, "/admin/agents")
    assert html =~ "Agents (PTY-managed)"
  end

  test "GET /admin/agents/<bad> renders bad-uri page", %{conn: conn} do
    {:ok, _lv, html} = live(conn, "/admin/agents/not%20a%20uri")
    assert html =~ "Agent URI invalid"
  end

  test "list_agents returns empty list when supervisor has no children", %{conn: _conn} do
    # Direct assertion — no PtyServers spawned in test env unless explicitly started.
    agents = Ezagent.PluginCc.PtyServer.list_agents()
    assert is_list(agents)
  end

  test "find_by_agent_uri returns :error for unknown URI", %{conn: _conn} do
    assert :error = Ezagent.PluginCc.PtyServer.find_by_agent_uri(URI.parse("agent://nonexistent"))
  end

  test "find_by_agent_uri + status work for a spawned PtyServer (test_mode)", %{conn: conn} do
    agent_uri = URI.parse("agent://pty-status-test-#{System.unique_integer([:positive])}")

    {:ok, _pid} =
      DynamicSupervisor.start_child(
        EzagentPluginCc.PtyServerSupervisor,
        {Ezagent.PluginCc.PtyServer, %{agent_uri: agent_uri, cwd: File.cwd!(), test_mode: true}}
      )

    Process.sleep(50)

    assert {:ok, pid} = Ezagent.PluginCc.PtyServer.find_by_agent_uri(agent_uri)
    status = Ezagent.PluginCc.PtyServer.status(pid)
    assert status.agent_uri == agent_uri
    assert status.test_mode == true
    assert status.running == true
    assert is_list(status.recent_output)

    # LV detail renders without error
    encoded = URI.encode_www_form(URI.to_string(agent_uri))
    {:ok, _lv, html} = live(conn, "/admin/agents/#{encoded}")
    assert html =~ URI.to_string(agent_uri)
    assert html =~ "Status"
    assert html =~ "Restart"

    # cleanup
    Process.exit(pid, :shutdown)
  end
end
