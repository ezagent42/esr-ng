defmodule EzagentWeb.ErrorHTMLTest do
  use EzagentWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template, only: [render_to_string: 4]

  test "renders 404.html — ezagent-branded with Activity Bar fallbacks" do
    # Phase 8c (Allen 2026-05-20): custom 404 page replaces plain "Not Found".
    # Asserts structural contract — branded, mentions the dead-end situation,
    # offers all three Activity Bar primary destinations as recovery links.
    html = render_to_string(EzagentWeb.ErrorHTML, "404", "html", [])
    assert html =~ "404 · not found"
    assert html =~ "ezagent"
    assert html =~ ~s(href="/sessions")
    assert html =~ ~s(href="/identities")
    assert html =~ ~s(href="/admin")
  end

  test "renders 500.html" do
    assert render_to_string(EzagentWeb.ErrorHTML, "500", "html", []) == "Internal Server Error"
  end
end
