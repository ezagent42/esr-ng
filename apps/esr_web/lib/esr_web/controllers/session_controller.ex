defmodule EsrWeb.SessionController do
  @moduledoc """
  Phase 4-completion Spec 05 §A.2.3 — controller-rendered login.

  Why not LiveView for login itself: LV-on-login adds a websocket
  dependency to credential entry. If WS can't connect, blank screen.
  Plain POST form is the robust path for the auth boundary.
  """
  use Phoenix.Controller, formats: [:html], layouts: []

  import Plug.Conn

  alias Esr.Users

  @login_html """
  <!DOCTYPE html>
  <html>
  <head>
    <title>ESR Login</title>
    <meta charset="utf-8">
    <style>
      body { font-family: -apple-system, sans-serif; max-width: 400px; margin: 80px auto; padding: 24px; }
      h1 { font-size: 24px; }
      form { display: flex; flex-direction: column; gap: 12px; }
      label { font-size: 13px; color: #666; }
      input { padding: 8px 10px; border: 1px solid #d1d5da; border-radius: 4px; font-size: 14px; }
      button { padding: 10px; background: #1f883d; color: white; border: none; border-radius: 4px; cursor: pointer; font-size: 14px; }
      .error { color: #cf222e; font-size: 13px; padding: 8px; background: #ffebe9; border-radius: 4px; margin-bottom: 8px; }
      .hint { color: #57606a; font-size: 12px; margin-top: 8px; }
    </style>
  </head>
  <body>
    <h1>ESR Login</h1>
    {{ERROR}}
    <form method="post" action="/login">
      <input type="hidden" name="_csrf_token" value="{{CSRF}}">
      <label for="user_uri">User URI</label>
      <input type="text" id="user_uri" name="user_uri" placeholder="user://allen" required autofocus>
      <label for="password">Password</label>
      <input type="password" id="password" name="password" required>
      <button type="submit">Sign in</button>
    </form>
    <p class="hint">
      First time? Admin runs <code>mix esr.user.set_password user://admin --password X</code>,
      then sign in as <code>user://admin</code>.
    </p>
  </body>
  </html>
  """

  def new(conn, _params) do
    err = flash_error(conn)
    error_block = if err, do: ~s(<div class="error">#{Plug.HTML.html_escape(err)}</div>), else: ""

    html =
      @login_html
      |> String.replace("{{ERROR}}", error_block)
      |> String.replace("{{CSRF}}", Plug.CSRFProtection.get_csrf_token())

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end

  def create(conn, %{"user_uri" => uri_str, "password" => password}) do
    case authenticate(uri_str, password) do
      :ok ->
        conn
        |> configure_session(renew: true)
        |> put_session(:current_user_uri, uri_str)
        |> redirect(to: "/admin")

      :error ->
        conn
        |> put_flash(:error, "Invalid URI or password.")
        |> redirect(to: "/login")
    end
  end

  def create(conn, _params) do
    conn
    |> put_flash(:error, "URI and password are required.")
    |> redirect(to: "/login")
  end

  def delete(conn, _params) do
    conn
    |> clear_session()
    |> redirect(to: "/login")
  end

  defp authenticate(uri_str, password) when is_binary(uri_str) and is_binary(password) do
    if Users.verify_password(uri_str, password) do
      :ok
    else
      :error
    end
  end

  defp flash_error(conn) do
    case conn.assigns[:flash] do
      %{} = flash -> Map.get(flash, "error")
      _ -> nil
    end
  end
end
