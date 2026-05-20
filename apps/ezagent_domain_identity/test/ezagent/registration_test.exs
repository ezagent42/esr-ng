defmodule Ezagent.RegistrationTest do
  use EzagentCore.DataCase, async: false

  alias Ezagent.Registration
  alias Ezagent.Entity.Profile

  test "derive_slug/1 lowercases and sanitizes the email local part" do
    assert Registration.derive_slug("Allen.Woods@example.com") == "allen-woods"
    assert Registration.derive_slug("a+tag@example.com") == "a-tag"
  end

  test "slug_available?/1 + suggest_slug/1" do
    assert Registration.slug_available?("freshslug")
    {:ok, _} = Ezagent.Users.create("entity://user/default/taken", nil, [])
    refute Registration.slug_available?("taken")
    assert Registration.suggest_slug("taken") == "taken-2"
  end

  test "domain_allowed?/1 checks the configured allowlist" do
    Ezagent.AppSettings.put("registration_domains", ["good.com"])
    assert Registration.domain_allowed?("x@good.com")
    refute Registration.domain_allowed?("x@bad.com")
  end

  test "domain_allowed?/1 is false when no domains are configured" do
    refute Registration.domain_allowed?("x@anything.com")
  end

  test "principal_for_email/1 resolves an existing profile" do
    {:ok, _} =
      Profile.upsert(%{
        entity_uri: "entity://user/default/known",
        display_name: "Known",
        email: "known@good.com"
      })

    assert Registration.principal_for_email("known@good.com") ==
             {:ok, URI.parse("entity://user/default/known")}

    assert Registration.principal_for_email("nobody@good.com") == :none
  end

  test "create_principal/3 creates user + profile + spawns the Kind" do
    assert {:ok, uri} =
             Registration.create_principal("newbie", "New Bie", "newbie@good.com")

    assert URI.to_string(uri) == "entity://user/default/newbie"
    assert Ezagent.Users.get_by_uri(uri) != nil
    assert Profile.by_email("newbie@good.com").entity_uri == "entity://user/default/newbie"
    assert {:ok, _pid} = Ezagent.KindRegistry.lookup(uri)
  end

  test "create_principal/3 rejects a taken slug" do
    {:ok, _} = Registration.create_principal("dup", "Dup", "dup1@good.com")
    assert {:error, :slug_taken} = Registration.create_principal("dup", "Dup2", "dup2@good.com")
  end
end
