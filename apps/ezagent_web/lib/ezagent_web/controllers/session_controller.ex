defmodule EzagentWeb.SessionController do
  @moduledoc """
  Phase 4-completion Spec 05 §A.2.3 — controller-rendered login.

  Why not LiveView for login itself: LV-on-login adds a websocket
  dependency to credential entry. If WS can't connect, blank screen.
  Plain POST form is the robust path for the auth boundary.

  Phase 8c follow-up (Allen 2026-05-20): unified login page. Previously
  /login (email) and /login/credentials (password) rendered as two
  separate pages, which was confusing — submit credentials then bounce
  to the email page made it look like login failed. Now ONE page at
  both URLs shows both forms (credentials primary, email secondary,
  with an inline notice when SMTP isn't configured).
  """
  use Phoenix.Controller, formats: [:html], layouts: []

  import Plug.Conn

  alias Ezagent.Entity
  alias EzagentWeb.SessionPrincipal

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
        --info-fg: #047857;
        --info-bg: #ecfdf5;
        --info-line: #a7f3d0;
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
        --info-fg: #6ee7b7;
        --info-bg: #022c1e;
        --info-line: #064e3b;
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
          --info-fg: #6ee7b7;
          --info-bg: #022c1e;
          --info-line: #064e3b;
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
      form { display: flex; flex-direction: column; gap: 10px; }
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
      button.secondary {
        background: var(--bg-input);
        color: var(--ink);
        border: 1px solid var(--line);
      }
      button.secondary:disabled {
        cursor: not-allowed;
        opacity: 0.5;
      }
      .error {
        color: var(--error-fg);
        font-size: 13px;
        padding: 10px 12px;
        background: var(--error-bg);
        border: 1px solid var(--error-line);
        border-radius: 8px;
        margin-bottom: 12px;
      }
      .info {
        color: var(--info-fg);
        font-size: 13px;
        padding: 10px 12px;
        background: var(--info-bg);
        border: 1px solid var(--info-line);
        border-radius: 8px;
        margin-bottom: 12px;
      }
      .divider {
        display: flex;
        align-items: center;
        gap: 10px;
        margin: 18px 0;
        color: var(--ink-dim);
        font-size: 11px;
        text-transform: uppercase;
        letter-spacing: 0.1em;
      }
      .divider::before, .divider::after {
        content: '';
        flex: 1;
        height: 1px;
        background: var(--line);
      }
      .section-label {
        font-size: 11px;
        text-transform: uppercase;
        letter-spacing: 0.08em;
        color: var(--ink-dim);
        margin: 0 0 8px;
        font-weight: 500;
      }
      .disabled-notice {
        font-size: 12px;
        color: var(--ink-dim);
        padding: 10px 12px;
        background: var(--bg-code);
        border: 1px dashed var(--line);
        border-radius: 8px;
      }
      .hint { color: var(--ink-dim); font-size: 12px; margin: 18px 0 0; line-height: 1.55; }
      code { font-family: var(--font-mono); font-size: 11px; background: var(--bg-code); padding: 1px 5px; border-radius: 3px; }
    </style>
  </head>
  <body>
    <div class="card">
      <p class="brand">ezagent</p>
      <h1>Sign in</h1>

      {{NOTICE}}

      <p class="section-label">With password</p>
      {{CRED_ERROR}}
      <form method="post" action="/login/credentials">
        <input type="hidden" name="_csrf_token" value="{{CSRF}}">
        <label for="entity_uri">Username or entity URI</label>
        <input type="text" id="entity_uri" name="entity_uri" placeholder="admin   or   entity://user/default/admin" required autofocus>
        <label for="secret">Password or token</label>
        <input type="password" id="secret" name="secret" required>
        <button type="submit">Sign in</button>
      </form>

      <div class="divider"><span>or</span></div>

      <p class="section-label">With email magic link</p>
      {{EMAIL_SECTION}}

      <p class="hint">
        Bare handles (<code>admin</code>) resolve to <code>entity://user/default/admin</code>.
        Full URIs (<code>entity://user/&lt;name&gt;</code> /
        <code>entity://agent/&lt;flavor&gt;_&lt;name&gt;</code>) also accepted.
        First-time admin: <code>mix ezagent.user.set_password entity://user/default/admin --password X</code>.
      </p>
    </div>
  </body>
  </html>
  """

  @email_form """
  <form method="post" action="/login">
    <input type="hidden" name="_csrf_token" value="{{CSRF}}">
    <label for="email">Email address</label>
    <input type="email" id="email" name="email" placeholder="you@example.com" required>
    <button type="submit" class="secondary">Email me a sign-in link</button>
  </form>
  """

  @email_disabled_notice """
  <p class="disabled-notice">Email sign-in is not enabled. An admin can turn it on in Settings → SMTP.</p>
  """

  # GET /login — unified login page with both credential and email forms.
  def new(conn, _params) do
    render_login_page(conn, [])
  end

  # POST /login — email magic-link submit. Renders the unified page with
  # an anti-enumeration "if that email can sign in, we've sent a link"
  # notice (identical response regardless of allowlist / rate-limit).
  def create(conn, %{"email" => email}) when is_binary(email) do
    email = email |> String.trim() |> String.downcase()
    _ = maybe_send_magic_link(conn, email)

    notice = ~s(<div class="info">If that email can sign in, we've sent a link. Please check your inbox.</div>)
    render_login_page(conn, notice: notice)
  end

  def create(conn, _params), do: new(conn, %{})

  # GET /login/credentials — back-compat alias for /login. Renders the
  # same unified page; kept so any cached bookmark / external link still
  # works rather than 404-ing.
  def credentials_new(conn, _params) do
    render_login_page(conn, [])
  end

  # POST /login/credentials — password submit. On success: canonical
  # entity:// URI stored in session, redirect to /sessions. On failure:
  # render unified page with inline error above the credentials form
  # (no separate page-bounce — that was the bug Allen reported
  # 2026-05-20).
  def credentials_create(conn, %{"entity_uri" => uri_str, "secret" => secret}) do
    case SessionPrincipal.canonicalize(uri_str) do
      canonical ->
        case authenticate(canonical, secret) do
          :ok ->
            conn
            |> SessionPrincipal.put(canonical)
            |> redirect(to: "/sessions")

          :error ->
            render_login_page(conn, cred_error: "Invalid URI or credentials.")
        end
    end
  rescue
    # User typed something that isn't a valid handle / URI at all
    # (e.g. "foo@bar.com" or whitespace) — same UX as bad credentials,
    # no enumeration leak.
    ArgumentError ->
      render_login_page(conn, cred_error: "Invalid URI or credentials.")
  end

  def credentials_create(conn, _params) do
    render_login_page(conn, cred_error: "Username/URI and password/token are required.")
  end

  def delete(conn, _params) do
    conn
    |> clear_session()
    |> redirect(to: "/login")
  end

  # --- internals ----------------------------------------------------

  defp render_login_page(conn, opts) do
    notice = Keyword.get(opts, :notice, "")
    cred_error = Keyword.get(opts, :cred_error)

    cred_error_html =
      if cred_error,
        do: ~s(<div class="error">) <> Plug.HTML.html_escape(cred_error) <> "</div>",
        else: ""

    email_section =
      if Ezagent.AppSettings.smtp_configured?() do
        String.replace(@email_form, "{{CSRF}}", Plug.CSRFProtection.get_csrf_token())
      else
        @email_disabled_notice
      end

    html =
      @login_html
      |> String.replace("{{NOTICE}}", notice)
      |> String.replace("{{CRED_ERROR}}", cred_error_html)
      |> String.replace("{{EMAIL_SECTION}}", email_section)
      |> String.replace("{{CSRF}}", Plug.CSRFProtection.get_csrf_token())

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end

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

  # Caller guarantees `uri_str` is already canonical
  # (`entity://user/...` or `entity://agent/...`) — `SessionPrincipal`
  # validated it before we got here.
  defp authenticate(uri_str, secret) when is_binary(uri_str) and is_binary(secret) do
    case Entity.authenticate(URI.parse(uri_str), secret) do
      {:ok, _} -> :ok
      {:error, _} -> :error
    end
  end
end
