defmodule EzagentWeb.SessionControllerTest do
  use EzagentCore.DataCase
  use Phoenix.ConnTest

  @endpoint EzagentWeb.Endpoint

  describe "GET /login (unified login page)" do
    test "renders the branded unified login (credentials + email sections)" do
      conn = build_conn() |> get("/login")
      body = html_response(conn, 200)
      # Branding (Phase 8c PR-A)
      assert body =~ "ezagent"
      assert body =~ "Sign in"
      # Credentials section
      assert body =~ "With password"
      assert body =~ ~s(action="/login/credentials")
      assert body =~ "Username or entity URI"
      # Email section header is always present; the inner form/notice
      # depends on SMTP config.
      assert body =~ "With email magic link"
    end

    test "/login/credentials renders the same unified page (back-compat)" do
      conn = build_conn() |> get("/login/credentials")
      body = html_response(conn, 200)
      assert body =~ "With password"
      assert body =~ "With email magic link"
    end

    # Regression: Allen 2026-05-20 — credentials form MUST POST to
    # /login/credentials. Posting to /login routes to the email handler,
    # which silently discards entity_uri/secret.
    test "form action targets /login/credentials, not /login" do
      conn = build_conn() |> get("/login")
      body = html_response(conn, 200)
      assert body =~ ~s(action="/login/credentials")
      refute body =~ ~s(action="/login")
    end
  end

  describe "POST /login/credentials" do
    test "happy path: valid creds → session set + redirect to /sessions" do
      uri = "entity://user/login-happy-#{System.unique_integer([:positive])}"
      {:ok, _} = Ezagent.Users.create(uri, "right-pw", [])

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{})
        |> post("/login/credentials", %{"entity_uri" => uri, "secret" => "right-pw"})

      assert redirected_to(conn) == "/sessions"
      assert Plug.Conn.get_session(conn, :current_entity_uri) == uri
    end

    test "bad password: renders unified page with inline cred error (no redirect)" do
      uri = "entity://user/login-bad-#{System.unique_integer([:positive])}"
      {:ok, _} = Ezagent.Users.create(uri, "right-pw", [])

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{})
        |> post("/login/credentials", %{"entity_uri" => uri, "secret" => "WRONG"})

      # Phase 8c follow-up: render inline (status 200) instead of
      # bouncing through a second redirect. Cookie still empty.
      body = html_response(conn, 200)
      assert body =~ "Invalid URI or credentials."
      assert body =~ "With password"
      refute Plug.Conn.get_session(conn, :current_entity_uri)
    end

    test "unknown user: renders unified page with inline cred error" do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{})
        |> post("/login/credentials", %{
          "entity_uri" => "entity://user/never-existed",
          "secret" => "x"
        })

      body = html_response(conn, 200)
      assert body =~ "Invalid URI or credentials."
    end

    # Regression: Allen 2026-05-20 (BUG) — bare handle "admin" succeeded
    # auth but the RAW input was put into the session as :current_entity_uri.
    # On the next request RequireEntity called URI.parse("admin") → no
    # scheme → bounced to /login. Login appeared to fail to the user.
    # Fix: store canonical "entity://user/admin", not raw "admin".
    test "bare handle stores CANONICAL entity:// URI in session (regression)" do
      handle = "barehandle#{System.unique_integer([:positive])}"
      uri = "entity://user/" <> handle
      {:ok, _} = Ezagent.Users.create(uri, "pw", [])

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{})
        |> post("/login/credentials", %{"entity_uri" => handle, "secret" => "pw"})

      assert redirected_to(conn) == "/sessions"
      # The critical invariant — NOT the raw handle.
      assert Plug.Conn.get_session(conn, :current_entity_uri) == uri
      refute Plug.Conn.get_session(conn, :current_entity_uri) == handle
    end

    test "bare handle is lowercased before lookup; canonical is stored" do
      uri = "entity://user/admincase#{System.unique_integer([:positive])}"
      {:ok, _} = Ezagent.Users.create(uri, "pw", [])

      handle = uri |> String.replace_prefix("entity://user/", "") |> String.upcase()

      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{})
        |> post("/login/credentials", %{"entity_uri" => handle, "secret" => "pw"})

      assert redirected_to(conn) == "/sessions"
      assert Plug.Conn.get_session(conn, :current_entity_uri) == uri
    end

    # Layer 3 of the 2026-05-20 defense-in-depth: ROUND-TRIP. This is
    # the test most directly mirroring Allen's reported experience:
    # bare-handle login succeeded but the next request bounced to
    # /login. None of the controller-only happy-path tests caught it
    # because they stop at the redirect. This test continues:
    # bare-handle POST -> take resulting session -> simulate next
    # request -> assert RequireEntity passes through.
    test "round-trip: bare-handle login → next request passes RequireEntity (regression)" do
      handle = "round#{System.unique_integer([:positive])}"
      uri = "entity://user/" <> handle
      {:ok, _} = Ezagent.Users.create(uri, "pw", [])

      login_conn =
        build_conn()
        |> Plug.Test.init_test_session(%{})
        |> post("/login/credentials", %{"entity_uri" => handle, "secret" => "pw"})

      # Cross-handler simulation: copy the principal slot the login
      # handler set into a brand-new conn, then drive it through the
      # downstream RequireEntity plug — the exact pipeline a real
      # follow-up request hits.
      principal = Plug.Conn.get_session(login_conn, :current_entity_uri)

      next_conn =
        Phoenix.ConnTest.build_conn(:get, "/sessions")
        |> Plug.Test.init_test_session(%{"current_entity_uri" => principal})
        |> EzagentWeb.Plugs.RequireEntity.call([])

      refute next_conn.halted, "RequireEntity should pass through; saw bounce — login is broken"
      assert next_conn.assigns.current_entity_uri.scheme == "entity"
      assert next_conn.assigns.current_entity_uri.host == "user"
    end
  end

  describe "POST /login (email magic link)" do
    test "renders unified page with anti-enumeration notice (regardless of email)" do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{})
        |> post("/login", %{"email" => "nobody@example.com"})

      body = html_response(conn, 200)
      assert body =~ "If that email can sign in"
      # Notice renders on the same unified page (not a separate template).
      assert body =~ "With password"
    end
  end

  describe "logout" do
    test "DELETE /logout clears session and redirects to /login" do
      conn =
        build_conn()
        |> Plug.Test.init_test_session(%{"current_entity_uri" => "entity://user/allen"})
        |> delete("/logout")

      assert redirected_to(conn) == "/login"
      refute Plug.Conn.get_session(conn, :current_entity_uri)
    end
  end
end
