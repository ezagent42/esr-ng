defmodule EzagentWeb.SessionControllerTest do
  use EzagentCore.DataCase
  use Phoenix.ConnTest

  @endpoint EzagentWeb.Endpoint

  describe "GET /login/credentials" do
    test "renders the credentials login form (Phase 8c PR-A branded)" do
      conn = build_conn() |> get("/login/credentials")
      body = html_response(conn, 200)
      # Phase 8c PR-A — branded boundary page (Geist font, "Sign in"
      # heading, "ezagent" lowercase brand). PR #152 moved this route
      # from /login to /login/credentials so /login can host the
      # magic-link form.
      assert body =~ "ezagent"
      assert body =~ "Sign in"
      assert body =~ "Entity URI"
    end
  end

  describe "POST /login" do
    test "happy path: valid creds → session set + redirect to /sessions" do
      uri = "entity://user/login-happy-#{System.unique_integer([:positive])}"
      {:ok, _} = Ezagent.Users.create(uri, "right-pw", [])

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{})
        |> post("/login/credentials", %{"entity_uri" => uri, "secret" => "right-pw"})

      # Phase 8 polish (Allen 2026-05-20) — landing page promoted from
      # /admin (now Dashboard) to /sessions (now default Activity).
      assert redirected_to(conn) == "/sessions"
      assert Plug.Conn.get_session(conn, :current_entity_uri) == uri
    end

    test "bad password: redirect to /login with flash error" do
      uri = "entity://user/login-bad-#{System.unique_integer([:positive])}"
      {:ok, _} = Ezagent.Users.create(uri, "right-pw", [])

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{})
        |> post("/login/credentials", %{"entity_uri" => uri, "secret" => "WRONG"})

      assert redirected_to(conn) == "/login/credentials"
      refute Plug.Conn.get_session(conn, :current_entity_uri)
    end

    test "unknown user: redirect to /login with flash error" do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{})
        |> post("/login/credentials", %{
          "entity_uri" => "entity://user/never-existed",
          "secret" => "x"
        })

      assert redirected_to(conn) == "/login/credentials"
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
