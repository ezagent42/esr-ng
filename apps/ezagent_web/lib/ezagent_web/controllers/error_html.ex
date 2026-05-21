defmodule EzagentWeb.ErrorHTML do
  @moduledoc """
  Renders error pages.

  - **404** (Phase 8c, Allen 2026-05-20): branded "not found" page;
    404s should be rare per memory `feedback_ui_no_misleading_buttons`.
  - **500** (V1 acceptance, Allen 2026-05-21): Next.js-style branded
    fallback with collapsible Debug info. Renders when phx hits an
    unhandled exception AND `debug_errors: false` (prod / explicit dev
    override). In dev with `debug_errors: true`, Plug.Debugger's rich
    REPL page renders instead (more useful for active development);
    this 500 page is the FALLBACK.

  ## Debug-info gating (the collapsible <details> section)

  `show_debug?/1` returns true when EITHER:
  - `:show_error_debug` app env is true (dev default), OR
  - the current session belongs to an admin (per `Ezagent.Identity.admin?/1`)

  Non-admins in prod see a clean "Something went wrong" page with no
  internal details. Admins always see the debug section (collapsed by
  default in prod; expanded by default in dev).
  """
  use EzagentWeb, :html

  embed_templates "error_html/*"

  # Bridge from Phoenix's `render("<code>.html", assigns)` into the
  # functions `embed_templates` compiled from `error_html/<code>.html.heex`.
  def render("404.html", assigns), do: unquote(:"404")(assigns)
  def render("500.html", assigns), do: unquote(:"500")(assigns)

  # Fallback for any non-templated status code.
  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end

  @doc """
  True when the debug `<details>` block on the 500 page should be
  rendered at all (visibility, not open-state).

  Returns true when:
  - `:show_error_debug` app env is set (dev default), OR
  - the current session is an admin
  """
  @spec show_debug?(Plug.Conn.t() | any()) :: boolean()
  def show_debug?(%Plug.Conn{} = conn) do
    Application.get_env(:ezagent_web, :show_error_debug, false) or admin_session?(conn)
  end

  def show_debug?(_), do: false

  @doc """
  True when the debug `<details>` should default to OPEN (not just
  visible). Dev opens by default; admin in prod sees it collapsed.
  """
  @spec debug_open?(Plug.Conn.t() | any()) :: boolean()
  def debug_open?(%Plug.Conn{}) do
    Application.get_env(:ezagent_web, :show_error_debug, false)
  end

  def debug_open?(_), do: false

  @doc """
  Human-readable reason the debug section is visible — shown in the
  summary so users understand why they can see internals.
  """
  @spec debug_reason(Plug.Conn.t() | any()) :: String.t()
  def debug_reason(%Plug.Conn{} = conn) do
    cond do
      Application.get_env(:ezagent_web, :show_error_debug, false) -> "dev env"
      admin_session?(conn) -> "you're admin"
      true -> "<hidden>"
    end
  end

  def debug_reason(_), do: "<hidden>"

  defp admin_session?(%Plug.Conn{} = conn) do
    try do
      case Plug.Conn.get_session(conn, :current_entity_uri) do
        nil -> false
        uri_str -> Ezagent.Identity.admin?(uri_str)
      end
    rescue
      # Defensive — error page must NEVER raise (cascading failure risk)
      _ -> false
    end
  end

  defp admin_session?(_), do: false
end
