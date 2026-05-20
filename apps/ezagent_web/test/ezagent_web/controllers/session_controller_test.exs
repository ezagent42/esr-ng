defmodule EzagentWeb.SessionControllerTest do
  use EzagentCore.DataCase
  use Phoenix.ConnTest

  @endpoint EzagentWeb.Endpoint

  describe "GET /login" do
    test "renders the login form" do
      conn = build_conn() |> get("/login/credentials")
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
        |> post("/login/credentials", %{"entity_uri" => uri, "secret" => "right-pw"})

      assert redirected_to(conn) == "/admin"
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

    # Regression: Allen 2026-05-20 — bare handle "admin" must be accepted as
    # shortcut for "entity://user/admin"; session stores canonical URI.
    test "bare handle: 'foo' → authenticates as entity://user/foo, session stores canonical URI" do
      handle = "barehandle#{System.unique_integer([:positive])}"
      uri = "entity://user/" <> handle
      {:ok, _} = Ezagent.Users.create(uri, "pw", [])

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{})
        |> post("/login/credentials", %{"entity_uri" => handle, "secret" => "pw"})

      assert redirected_to(conn) == "/admin"
      assert Plug.Conn.get_session(conn, :current_entity_uri) == uri
    end

    # Regression: Allen 2026-05-20 — bare handle case-insensitive lowercasing.
    test "bare handle is lowercased before lookup" do
      uri = "entity://user/admincase#{System.unique_integer([:positive])}"
      {:ok, _} = Ezagent.Users.create(uri, "pw", [])

      # Compose the mixed-case handle the user might type
      handle = uri |> String.replace_prefix("entity://user/", "") |> String.upcase()

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{})
        |> post("/login/credentials", %{"entity_uri" => handle, "secret" => "pw"})

      assert redirected_to(conn) == "/admin"
      assert Plug.Conn.get_session(conn, :current_entity_uri) == uri
    end
  end

  describe "credentials form" do
    # Regression: Allen 2026-05-20 — the credentials form MUST POST to
    # /login/credentials. Posting to /login routes to the email handler,
    # which silently discards entity_uri/secret and re-renders the email
    # page ("Email sign-in is not enabled yet"). This test guards the
    # form action so a future template edit can't reintroduce the bug.
    test "form action targets /login/credentials, not /login" do
      conn = build_conn() |> get("/login/credentials")
      body = html_response(conn, 200)
      assert body =~ ~s(action="/login/credentials")
      refute body =~ ~s(action="/login")
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
