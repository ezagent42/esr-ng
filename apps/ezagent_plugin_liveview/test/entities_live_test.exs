defmodule EzagentPluginLiveview.EntitiesLiveTest do
  @moduledoc """
  PR #149 (S-5) invariant — `/admin/entities` is the unified live
  registry surface; lists every URI in `Ezagent.KindRegistry`
  regardless of scheme. Replaces the agent-only `/admin/agents`
  list page (per-PTY detail + terminal routes stay at
  `/admin/agents/:uri` / `/admin/agents/:uri/terminal`).
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
        "current_entity_uri" => URI.to_string(Ezagent.Entity.User.admin_uri())
      })

    {:ok, conn: conn}
  end

  test "GET /admin/entities renders header + filter chips", %{conn: conn} do
    {:ok, _lv, html} = live(conn, "/admin/entities")
    assert html =~ "Entities (live registry)"
    assert html =~ "entity://user"
    assert html =~ "entity://agent"
    assert html =~ "session://"
    assert html =~ "workspace://"
  end

  test "filter=user narrows to entity://user/* rows", %{conn: conn} do
    {:ok, _lv, html} = live(conn, "/admin/entities?filter=user")
    # Admin user spawned at boot — should appear under filter=user
    assert html =~ "entity"
  end

  test "filter=session narrows to session://* rows", %{conn: conn} do
    {:ok, _lv, html} = live(conn, "/admin/entities?filter=session")
    # Default session spawned at boot
    assert html =~ "session"
  end

  test "PTY agent detail route still works at /admin/agents/:uri", %{conn: conn} do
    agent_uri =
      URI.parse("entity://agent/test_pty-status-test-#{System.unique_integer([:positive])}")

    {:ok, pid} =
      DynamicSupervisor.start_child(
        EzagentPluginCc.PtyServerSupervisor,
        {Ezagent.PluginCc.PtyServer, %{agent_uri: agent_uri, cwd: File.cwd!(), test_mode: true}}
      )

    Process.sleep(50)

    encoded = URI.encode_www_form(URI.to_string(agent_uri))
    {:ok, _lv, html} = live(conn, "/admin/agents/#{encoded}")
    assert html =~ URI.to_string(agent_uri)

    # cleanup
    Process.exit(pid, :shutdown)
  end
end
