defmodule EzagentWeb.ErrorHTML do
  @moduledoc """
  Renders error pages. Phase 8c (Allen 2026-05-20): custom 404 page.

  404s should be rare — every UI element MUST point at a live destination
  (see memory `feedback_ui_no_misleading_buttons`). This page exists for
  the unexpected: stale bookmarks, typed URLs, deleted resources. It
  navigates users back to the Activity Bar surface they know, without
  pretending the missing page "moved" somewhere.
  """
  use EzagentWeb, :html

  embed_templates "error_html/*"

  # Bridge from Phoenix's `render("404.html", assigns)` call into the
  # function `embed_templates` compiled from `error_html/404.html.heex`.
  def render("404.html", assigns), do: unquote(:"404")(assigns)

  # Fallback for any non-templated status code.
  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
