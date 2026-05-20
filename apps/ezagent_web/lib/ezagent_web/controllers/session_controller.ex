defmodule EzagentWeb.SessionController do
  @moduledoc """
  Phase 4-completion Spec 05 §A.2.3 — controller-rendered login.

  Why not LiveView for login itself: LV-on-login adds a websocket
  dependency to credential entry. If WS can't connect, blank screen.
  Plain POST form is the robust path for the auth boundary.
  """
  use Phoenix.Controller, formats: [:html], layouts: []

  import Plug.Conn

  alias Ezagent.Entity

  @login_html """
  <!DOCTYPE html>
  <html>
  <head>
    <title>Ezagent Login</title>
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
    <h1>Ezagent Login</h1>
    {{ERROR}}
    <form method="post" action="/login">
      <input type="hidden" name="_csrf_token" value="{{CSRF}}">
      <label for="entity_uri">Entity URI</label>
      <input type="text" id="entity_uri" name="entity_uri" placeholder="entity://user/allen" required autofocus>
      <label for="secret">Password / Token</label>
      <input type="password" id="secret" name="secret" required>
      <button type="submit">Sign in</button>
    </form>
    <p class="hint">
      First time? Admin runs <code>mix ezagent.user.set_password entity://user/admin --password X</code>,
      then sign in as <code>entity://user/admin</code>. Agent URIs
      (<code>entity://agent/&lt;flavor&gt;_&lt;name&gt;</code>) sign in with a bearer token
      minted via the entity_tokens admin.
    </p>
  </body>
  </html>
  """

  @email_html """
  <!DOCTYPE html>
  <html><head><title>Ezagent Sign in</title><meta charset="utf-8">
  <style>
    body { font-family: -apple-system, sans-serif; max-width: 400px; margin: 80px auto; padding: 24px; }
    h1 { font-size: 24px; } form { display: flex; flex-direction: column; gap: 12px; }
    input { padding: 8px 10px; border: 1px solid #d1d5da; border-radius: 4px; font-size: 14px; }
    button { padding: 10px; background: #1f883d; color: white; border: none; border-radius: 4px; cursor: pointer; }
    .msg { color: #1f883d; font-size: 13px; padding: 8px; background: #e6ffec; border-radius: 4px; }
    .err { color: #cf222e; font-size: 13px; padding: 8px; background: #ffebe9; border-radius: 4px; }
    .hint { color: #57606a; font-size: 12px; margin-top: 8px; }
  </style></head><body>
  <h1>Sign in to Ezagent</h1>
  {{BODY}}
  <p class="hint"><a href="/login/credentials">Sign in with credentials</a> (admin / agent)</p>
  </body></html>
  """

  @email_form """
  <form method="post" action="/login">
    <input type="hidden" name="_csrf_token" value="{{CSRF}}">
    <label for="email">Email address</label>
    <input type="email" id="email" name="email" placeholder="you@example.com" required autofocus>
    <button type="submit">Email me a sign-in link</button>
  </form>
  """

  def new(conn, _params) do
    body =
      if Ezagent.AppSettings.smtp_configured?() do
        String.replace(@email_form, "{{CSRF}}", Plug.CSRFProtection.get_csrf_token())
      else
        ~s(<div class="err">Email sign-in is not enabled yet. Contact your administrator.</div>)
      end

    send_page(conn, String.replace(@email_html, "{{BODY}}", body))
  end

  def create(conn, %{"email" => email}) when is_binary(email) do
    email = email |> String.trim() |> String.downcase()
    _ = maybe_send_magic_link(conn, email)

    # Anti-enumeration: identical response regardless of whether the
    # email exists, is allowlisted, or was rate-limited (design §5.5).
    body =
      ~s(<div class="msg">If that email can sign in, we've sent a link. Please check your inbox.</div>)

    send_page(conn, String.replace(@email_html, "{{BODY}}", body))
  end

  def create(conn, _params), do: new(conn, %{})

  # Returns :ok always (caller ignores it — anti-enumeration). Internally
  # decides whether to actually mint + send.
  defp maybe_send_magic_link(conn, email) do
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()

    with true <- Ezagent.AppSettings.smtp_configured?(),
         :ok <-
           EzagentWeb.RateLimiter.check("login_email:" <> email, limit: 3, window_ms: 15 * 60_000),
         :ok <-
           EzagentWeb.RateLimiter.check("login_ip:" <> ip, limit: 10, window_ms: 60 * 60_000),
         true <- send_allowed?(email) do
      {:ok, raw} = Ezagent.Entity.MagicLinkToken.mint(email)
      link = EzagentWeb.Endpoint.url() <> "/auth/magic/" <> raw
      _ = EzagentWeb.Mailer.deliver_magic_link(email, link)
      :ok
    else
      _ -> :ok
    end
  end

  # Existing principal -> always allowed (login). New email -> must be
  # on the registration domain allowlist.
  defp send_allowed?(email) do
    case Ezagent.Registration.principal_for_email(email) do
      {:ok, _uri} -> true
      :none -> Ezagent.Registration.domain_allowed?(email)
    end
  end

  defp send_page(conn, html) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end

  def credentials_new(conn, _params) do
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

  def credentials_create(conn, %{"entity_uri" => uri_str, "secret" => secret}) do
    case authenticate(uri_str, secret) do
      :ok ->
        conn
        |> configure_session(renew: true)
        |> put_session(:current_entity_uri, uri_str)
        |> redirect(to: "/admin")

      :error ->
        conn
        |> put_flash(:error, "Invalid URI or credentials.")
        |> redirect(to: "/login/credentials")
    end
  end

  def credentials_create(conn, _params) do
    conn
    |> put_flash(:error, "Entity URI and credentials are required.")
    |> redirect(to: "/login/credentials")
  end

  def delete(conn, _params) do
    conn
    |> clear_session()
    |> redirect(to: "/login")
  end

  defp authenticate(uri_str, secret) when is_binary(uri_str) and is_binary(secret) do
    case URI.parse(uri_str) do
      %URI{scheme: "entity"} = uri ->
        case Entity.authenticate(uri, secret) do
          {:ok, _} -> :ok
          {:error, _} -> :error
        end

      _ ->
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
