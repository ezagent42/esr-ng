defmodule EzagentWeb.WorkspaceSwitchControllerTest do
  @moduledoc """
  Phase 9 PR-5 (SPEC v3 §6.4 amended) — workspace switcher tests.

  Per Allen's correction 2026-05-21: workspace switch is logout +
  re-auth, NOT in-place context swap. These tests verify:

  - Known workspace → 302 to /login?workspace=<target>, BOTH session
    slots cleared.
  - Unknown workspace → 302 to /sessions, flash error, session
    UNCHANGED.
  - Missing param → 302 to /sessions with flash error.
  """
  use EzagentCore.DataCase
  use Phoenix.ConnTest

  @endpoint EzagentWeb.Endpoint

  setup do
    # Unique-per-test workspace + user so the sandbox rollback isn't
    # racing with shared fixtures (see EzagentCore.DataCase — shared
    # ownership when async: false).
    ws_name = "team-#{System.unique_integer([:positive])}"
    {:ok, _} = Ezagent.Workspace.Store.create(ws_name, %{})

    uri = "entity://user/default/wsswitch-#{System.unique_integer([:positive])}"
    {:ok, _} = Ezagent.Users.create(uri, "pw", [])

    %{logged_in_uri: uri, target_workspace: ws_name}
  end

  describe "POST /workspaces/switch" do
    test "happy path: known workspace → 302 to /login?workspace=<target> + session cleared",
         %{logged_in_uri: uri, target_workspace: target} do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{
          "current_entity_uri" => uri,
          "current_workspace_uri" => "workspace://default"
        })
        |> post("/workspaces/switch", %{"workspace" => target})

      assert redirected_to(conn) == "/login?workspace=" <> target
      refute Plug.Conn.get_session(conn, :current_entity_uri)
      refute Plug.Conn.get_session(conn, :current_workspace_uri)
    end

    test "unknown workspace: → 302 to /sessions, flash error, session UNCHANGED",
         %{logged_in_uri: uri} do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{
          "current_entity_uri" => uri,
          "current_workspace_uri" => "workspace://default"
        })
        |> post("/workspaces/switch", %{"workspace" => "no-such-workspace"})

      assert redirected_to(conn) == "/sessions"
      # Session preserved — user can keep using their current workspace.
      assert Plug.Conn.get_session(conn, :current_entity_uri) == uri
      assert Plug.Conn.get_session(conn, :current_workspace_uri) == "workspace://default"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Unknown workspace"
    end

    test "missing workspace param: → 302 to /sessions, flash error",
         %{logged_in_uri: uri} do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{"current_entity_uri" => uri})
        |> post("/workspaces/switch", %{})

      assert redirected_to(conn) == "/sessions"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Missing workspace"
    end

    test "anonymous (no session) is bounced by RequireEntity before reaching the controller",
         %{target_workspace: target} do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{})
        |> post("/workspaces/switch", %{"workspace" => target})

      # RequireEntity catches the unauthenticated request and redirects
      # to /login — the switch endpoint is mounted inside that pipeline
      # for exactly this reason (no anonymous session-clearing spam).
      assert redirected_to(conn) =~ "/login"
    end
  end
end
