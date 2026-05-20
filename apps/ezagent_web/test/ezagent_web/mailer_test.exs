defmodule EzagentWeb.MailerTest do
  use ExUnit.Case, async: true

  alias EzagentWeb.Mailer

  test "build_magic_link_email/2 sets recipient, sender, and link in the body" do
    email =
      Mailer.build_magic_link_email("allen@example.com",
        url: "https://esr.example.com/auth/magic/abc123",
        from_address: "no-reply@esr.example.com"
      )

    assert Enum.any?(email.to, fn {_name, addr} -> addr == "allen@example.com" end)
    assert {_, "no-reply@esr.example.com"} = email.from
    assert email.subject =~ "Ezagent"
    assert email.text_body =~ "https://esr.example.com/auth/magic/abc123"
    assert email.html_body =~ "https://esr.example.com/auth/magic/abc123"
  end
end
