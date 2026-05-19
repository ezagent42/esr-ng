defmodule EzagentWeb.SessionControllerTest do
  use EzagentCore.DataCase
  use Phoenix.ConnTest

  @endpoint EzagentWeb.Endpoint

  describe "GET /login" do
    test "renders the login form" do
      conn = build_conn() |> get("/login")
      assert html_response(conn, 200) =~ "Ezagent Login"
      assert html_response(conn, 200) =~ "Entity URI"
    end
  end

  describe "POST /login" do
    test "happy path: valid creds → session set + redirect to /admin" do
      uri = "entity://user/login-happy-#{System.unique_integer([:positive])}"
      {:ok, _} = Ezagent.Users.create(uri, "right-pw", [])

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{})
        |> post("/login", %{"entity_uri" => uri, "secret" => "right-pw"})

      assert redirected_to(conn) == "/admin"
      assert Plug.Conn.get_session(conn, :current_entity_uri) == uri
    end

    test "bad password: redirect to /login with flash error" do
      uri = "entity://user/login-bad-#{System.unique_integer([:positive])}"
      {:ok, _} = Ezagent.Users.create(uri, "right-pw", [])

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{})
        |> post("/login", %{"entity_uri" => uri, "secret" => "WRONG"})

      assert redirected_to(conn) == "/login"
      refute Plug.Conn.get_session(conn, :current_entity_uri)
    end

    test "unknown user: redirect to /login with flash error" do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{})
        |> post("/login", %{"entity_uri" => "entity://user/never-existed", "secret" => "x"})

      assert redirected_to(conn) == "/login"
    end
  end

  describe "logout" do
    test "DELETE /logout clears session and redirects" do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{"current_entity_uri" => "entity://user/allen"})
        |> delete("/logout")

      assert redirected_to(conn) == "/login"
      refute Plug.Conn.get_session(conn, :current_entity_uri)
    end
  end
end
