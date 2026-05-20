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
  <html lang="en">
  <head>
    <title>ezagent · sign in</title>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Geist:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap">
    <style>
      :root {
        --font-sans: 'Geist', ui-sans-serif, system-ui, -apple-system, sans-serif;
        --font-mono: 'JetBrains Mono', ui-monospace, Menlo, monospace;
        --ink: #0a0a0a;
        --ink-dim: #525252;
        --line: #e5e5e5;
        --accent: #1f883d;
        --accent-faint: #e6f4ea;
        --bg-page: #fafafa;
        --bg-card: #ffffff;
        --bg-input: #ffffff;
        --bg-code: #f4f4f5;
        --error-fg: #b91c1c;
        --error-bg: #fef2f2;
        --error-line: #fecaca;
        --btn-fg: #ffffff;
      }
      /* Phase 8c PR-D — explicit theme + system-pref fallback. The
         login page renders before the LV WS, so we honor both
         data-theme=dark (set by the toggle JS) and the prefers-color-scheme. */
      :root[data-theme="dark"] {
        --ink: #fafafa;
        --ink-dim: #a3a3a3;
        --line: #27272a;
        --accent: #4ade80;
        --accent-faint: #052e16;
        --bg-page: #09090b;
        --bg-card: #18181b;
        --bg-input: #18181b;
        --bg-code: #27272a;
        --error-fg: #fca5a5;
        --error-bg: #450a0a;
        --error-line: #7f1d1d;
        --btn-fg: #18181b;
      }
      @media (prefers-color-scheme: dark) {
        :root:not([data-theme="light"]) {
          --ink: #fafafa;
          --ink-dim: #a3a3a3;
          --line: #27272a;
          --accent: #4ade80;
          --accent-faint: #052e16;
          --bg-page: #09090b;
          --bg-card: #18181b;
          --bg-input: #18181b;
          --bg-code: #27272a;
          --error-fg: #fca5a5;
          --error-bg: #450a0a;
          --error-line: #7f1d1d;
          --btn-fg: #18181b;
        }
      }
      * { box-sizing: border-box; }
      html, body { height: 100%; }
      body {
        margin: 0;
        font-family: var(--font-sans);
        color: var(--ink);
        background:
          radial-gradient(circle at 0% 0%, rgba(31,136,61,0.04), transparent 40%),
          radial-gradient(circle at 100% 100%, rgba(10,10,10,0.03), transparent 40%),
          var(--bg-page);
        display: grid;
        place-items: center;
        padding: 24px;
      }
      .card {
        width: 100%;
        max-width: 380px;
        background: var(--bg-card);
        border: 1px solid var(--line);
        border-radius: 12px;
        padding: 32px 28px;
        box-shadow: 0 1px 0 rgba(0,0,0,0.02), 0 8px 24px -12px rgba(0,0,0,0.06);
      }
      .brand {
        font-family: var(--font-mono);
        font-size: 12px;
        letter-spacing: 0.12em;
        color: var(--ink-dim);
        text-transform: uppercase;
        margin: 0 0 4px;
      }
      h1 { font-size: 22px; font-weight: 600; margin: 0 0 24px; letter-spacing: -0.01em; }
      form { display: flex; flex-direction: column; gap: 14px; }
      label { font-size: 12px; color: var(--ink-dim); font-weight: 500; }
      input {
        padding: 10px 12px;
        border: 1px solid var(--line);
        border-radius: 8px;
        font-size: 14px;
        font-family: var(--font-mono);
        background: var(--bg-input);
        color: var(--ink);
        transition: border-color 120ms ease;
      }
      input:focus { outline: none; border-color: var(--accent); box-shadow: 0 0 0 3px var(--accent-faint); }
      button {
        margin-top: 4px;
        padding: 10px 14px;
        background: var(--ink);
        color: var(--btn-fg);
        border: none;
        border-radius: 8px;
        font-size: 14px;
        font-weight: 500;
        font-family: var(--font-sans);
        cursor: pointer;
        transition: opacity 120ms ease;
      }
      button:hover { opacity: 0.85; }
      .error {
        color: var(--error-fg);
        font-size: 13px;
        padding: 10px 12px;
        background: var(--error-bg);
        border: 1px solid var(--error-line);
        border-radius: 8px;
        margin-bottom: 8px;
      }
      .hint { color: var(--ink-dim); font-size: 12px; margin: 16px 0 0; line-height: 1.55; }
      code { font-family: var(--font-mono); font-size: 11px; background: var(--bg-code); padding: 1px 5px; border-radius: 3px; }
    </style>
  </head>
  <body>
    <div class="card">
      <p class="brand">ezagent</p>
      <h1>Sign in</h1>
      {{ERROR}}
      <form method="post" action="/login/credentials">
        <input type="hidden" name="_csrf_token" value="{{CSRF}}">
        <label for="entity_uri">Username or Entity URI</label>
        <input type="text" id="entity_uri" name="entity_uri" placeholder="admin   or   entity://user/admin" required autofocus>
        <label for="secret">Password or token</label>
        <input type="password" id="secret" name="secret" required>
        <button type="submit">Sign in</button>
      </form>
      <p class="hint">
        Bare handles (<code>admin</code>) resolve to <code>entity://user/admin</code>.
        Full URIs (<code>entity://user/&lt;name&gt;</code> /
        <code>entity://agent/&lt;flavor&gt;_&lt;name&gt;</code>) also accepted.
        First-time admin password setup: <code>mix ezagent.user.set_password entity://user/admin --password X</code>.
      </p>
    </div>
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
        |> redirect(to: "/sessions")

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
    case URI.parse(normalize_principal(uri_str)) do
      %URI{scheme: "entity"} = uri ->
        case Entity.authenticate(uri, secret) do
          {:ok, _} -> :ok
          {:error, _} -> :error
        end

      _ ->
        :error
    end
  end

  # Phase 8c follow-up (Allen 2026-05-20) — accept bare handles at the
  # credentials login: "admin" → "entity://user/admin", "allen" →
  # "entity://user/allen". Full `entity://...` URIs pass through
  # unchanged so existing flows / scripts keep working.
  #
  # Display name is intentionally NOT accepted as a login key — it's
  # not unique (two entities can share the same display name).
  defp normalize_principal(input) do
    trimmed = String.trim(input)

    cond do
      String.starts_with?(trimmed, "entity://") ->
        trimmed

      # bare handle: alphanumerics + dash/underscore, no slashes or @
      String.match?(trimmed, ~r/^[a-zA-Z0-9_-]+$/) ->
        "entity://user/" <> String.downcase(trimmed)

      # anything else — let URI.parse classify it as :error
      true ->
        trimmed
    end
  end

  defp flash_error(conn) do
    case conn.assigns[:flash] do
      %{} = flash -> Map.get(flash, "error")
      _ -> nil
    end
  end
end
