defmodule EzagentWeb.LoginEmailTest do
  use EzagentWeb.ConnCase

  alias EzagentWeb.RateLimiter

  setup do
    RateLimiter.reset_all()

    Ezagent.AppSettings.put("smtp_config", %{
      "host" => "localhost",
      "port" => 2525,
      "username" => "u",
      "password" => "p",
      "from_address" => "no-reply@test.local"
    })

    Ezagent.AppSettings.put("registration_domains", ["good.com"])
    :ok
  end

  test "GET /login renders the email form", %{conn: conn} do
    conn = get(conn, "/login")
    assert html_response(conn, 200) =~ "email"
  end

  test "POST /login with any email shows the generic check-inbox response", %{conn: conn} do
    conn = post(conn, "/login", %{"email" => "someone@bad.com"})
    assert html_response(conn, 200) =~ "check"
  end

  test "POST /login mints a token for an allowlisted new email", %{conn: conn} do
    post(conn, "/login", %{"email" => "fresh@good.com"})
    assert EzagentCore.Repo.aggregate(Ezagent.Entity.MagicLinkToken, :count) >= 1
  end

  test "POST /login mints no token for a non-allowlisted new email", %{conn: conn} do
    before = EzagentCore.Repo.aggregate(Ezagent.Entity.MagicLinkToken, :count)
    post(conn, "/login", %{"email" => "fresh@bad.com"})
    assert EzagentCore.Repo.aggregate(Ezagent.Entity.MagicLinkToken, :count) == before
  end
end
