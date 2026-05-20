defmodule EzagentWeb.MagicLinkControllerTest do
  use EzagentWeb.ConnCase

  alias Ezagent.Entity.{MagicLinkToken, Profile}

  test "consuming a token for an existing user logs them in", %{conn: conn} do
    {:ok, _} =
      Profile.upsert(%{
        entity_uri: "entity://user/default/known",
        display_name: "Known",
        email: "known@good.com"
      })

    {:ok, _} = Ezagent.Users.create("entity://user/default/known", nil, [])
    {:ok, raw} = MagicLinkToken.mint("known@good.com")

    conn = get(conn, "/auth/magic/#{raw}")
    assert redirected_to(conn) == "/sessions"
    assert get_session(conn, :current_entity_uri) == "entity://user/default/known"
  end

  test "consuming a token for a new email starts registration", %{conn: conn} do
    {:ok, raw} = MagicLinkToken.mint("newcomer@good.com")

    conn = get(conn, "/auth/magic/#{raw}")
    assert redirected_to(conn) == "/register/complete"
    assert get_session(conn, :pending_registration_email) == "newcomer@good.com"
  end

  test "an invalid token redirects to /login with an error", %{conn: conn} do
    conn = get(conn, "/auth/magic/bogus-token")
    assert redirected_to(conn) == "/login"
  end

  test "a consumed token cannot be reused", %{conn: conn} do
    {:ok, raw} = MagicLinkToken.mint("again@good.com")
    get(build_conn(), "/auth/magic/#{raw}")
    conn = get(conn, "/auth/magic/#{raw}")
    assert redirected_to(conn) == "/login"
  end
end
