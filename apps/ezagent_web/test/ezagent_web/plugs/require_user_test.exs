defmodule EzagentWeb.Plugs.RequireUserTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias EzagentWeb.Plugs.RequireUser

  describe "RequireUser plug" do
    test "redirects to /login + halts when no session" do
      conn =
        conn(:get, "/admin")
        |> init_test_session(%{})
        |> RequireUser.call([])

      assert conn.halted
      assert ["/login"] = get_resp_header(conn, "location")
    end

    test "passes through and assigns :current_user_uri when session present" do
      conn =
        conn(:get, "/admin")
        |> init_test_session(%{"current_user_uri" => "user://allen"})
        |> RequireUser.call([])

      refute conn.halted
      assert %URI{scheme: "user", host: "allen"} = conn.assigns.current_user_uri
    end
  end
end
