defmodule Ezagent.AppSettingsTest do
  use EzagentCore.DataCase, async: false

  alias Ezagent.AppSettings

  test "put/2 then get/1 round-trips a JSON-able term" do
    :ok = AppSettings.put("registration_domains", ["a.com", "b.com"])
    assert AppSettings.get("registration_domains") == ["a.com", "b.com"]
  end

  test "put/2 upserts" do
    :ok = AppSettings.put("registration_domains", ["a.com"])
    :ok = AppSettings.put("registration_domains", ["a.com", "c.com"])
    assert AppSettings.get("registration_domains") == ["a.com", "c.com"]
  end

  test "get/1 returns nil for an unset key" do
    assert AppSettings.get("nope") == nil
  end

  test "smtp_configured?/0 is false until a complete smtp_config is set" do
    refute AppSettings.smtp_configured?()

    :ok = AppSettings.put("smtp_config", %{"host" => "smtp.x.com"})
    refute AppSettings.smtp_configured?()

    :ok =
      AppSettings.put("smtp_config", %{
        "host" => "smtp.x.com",
        "port" => 587,
        "username" => "u",
        "password" => "p",
        "from_address" => "no-reply@x.com"
      })

    assert AppSettings.smtp_configured?()
  end
end
