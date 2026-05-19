defmodule EzagentWeb.Plugs.RequireEntityTest do
  @moduledoc """
  PR #142 — RequireUser renamed to RequireEntity. Session key
  `current_user_uri` renamed to `current_entity_uri`. The plug
  now accepts both entity://user/* and entity://agent/* URIs in
  the session (any entity, not just users).
  """
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias EzagentWeb.Plugs.RequireEntity

  describe "RequireEntity plug" do
    test "redirects to /login + halts when no session" do
      conn =
        conn(:get, "/admin")
        |> init_test_session(%{})
        |> RequireEntity.call([])

      assert conn.halted
      assert ["/login"] = get_resp_header(conn, "location")
    end

    test "passes through + assigns current_entity_uri for entity://user/*" do
      conn =
        conn(:get, "/admin")
        |> init_test_session(%{"current_entity_uri" => "entity://user/admin"})
        |> RequireEntity.call([])

      refute conn.halted
      assert %URI{scheme: "entity", host: "user", path: "/admin"} = conn.assigns.current_entity_uri
    end

    test "passes through + assigns current_entity_uri for entity://agent/*" do
      conn =
        conn(:get, "/admin")
        |> init_test_session(%{"current_entity_uri" => "entity://agent/cc_test"})
        |> RequireEntity.call([])

      refute conn.halted
      assert %URI{scheme: "entity", host: "agent", path: "/cc_test"} = conn.assigns.current_entity_uri
    end

    test "rejects malformed (non-entity scheme) session URI" do
      conn =
        conn(:get, "/admin")
        |> init_test_session(%{"current_entity_uri" => "session://default/main"})
        |> RequireEntity.call([])

      assert conn.halted
      assert ["/login"] = get_resp_header(conn, "location")
    end
  end
end
