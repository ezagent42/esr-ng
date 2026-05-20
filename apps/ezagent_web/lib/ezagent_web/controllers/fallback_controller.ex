defmodule EzagentWeb.FallbackController do
  @moduledoc """
  Phase 8c — catch-all for unmatched browser GETs. Renders the
  ezagent-branded 404 page (`EzagentWeb.ErrorHTML.404.html`) so dev
  and prod show the same surface to end users.

  Without this, Phoenix dev's `debug_errors: true` serves the
  stacktrace exception page for missing routes — useful for *us*, but
  misleading as a measure of "what does a 404 look like." This route
  forces the real ErrorHTML rendering at dev time too.

  See memory `feedback_ui_no_misleading_buttons` for the rule that
  404s should never be a planned destination of any UI element.
  """
  use EzagentWeb, :controller

  def not_found(conn, _params) do
    conn
    |> put_status(:not_found)
    |> put_view(EzagentWeb.ErrorHTML)
    |> render(:"404")
  end
end
