defmodule Esr.Template.FeishuChatBindingTest do
  @moduledoc """
  Phase 5 Plan B invariant — Feishu chat_binding Template Class spawns
  a real `feishu://oc_xxx` Receiver Kind and adds a session-scoped
  routing rule. Outbound is no longer a side-channel; it goes through
  Resolver → dispatch → Behavior.

  If this test breaks, the Feishu plugin has drifted back toward the
  PubSub-subscriber pattern that Allen flagged on 2026-05-17.
  """
  use ExUnit.Case, async: false

  alias Esr.Template.FeishuChatBinding

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(EsrCore.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(EsrCore.Repo, {:shared, self()})
    :ok
  end

  test "validate enforces session:// + oc_ prefix" do
    assert :ok =
             FeishuChatBinding.validate(%{
               "class" => "feishu.chat_binding",
               "session_uri" => "session://main",
               "chat_id" => "oc_abc"
             })

    assert {:error, _} =
             FeishuChatBinding.validate(%{
               "class" => "feishu.chat_binding",
               "session_uri" => "user://x",
               "chat_id" => "oc_abc"
             })

    assert {:error, :chat_id_must_start_with_oc_} =
             FeishuChatBinding.validate(%{
               "class" => "feishu.chat_binding",
               "session_uri" => "session://main",
               "chat_id" => "wrong"
             })
  end

  test "instantiate spawns Feishu Receiver Kind + adds session-scoped routing rule" do
    chat_id = "oc_test_#{System.unique_integer([:positive])}"
    session_uri_str = "session://b-test-#{System.unique_integer([:positive])}"
    session_uri = URI.parse(session_uri_str)

    assert {:ok, [feishu_uri]} =
             FeishuChatBinding.instantiate(
               "main",
               %{"session_uri" => session_uri_str, "chat_id" => chat_id},
               URI.parse("workspace://test")
             )

    assert feishu_uri == URI.parse("feishu://#{chat_id}")

    # Kind alive in KindRegistry
    assert {:ok, _pid} = Esr.KindRegistry.lookup(feishu_uri)

    # Routing rule exists, scoped to session
    rules = Esr.Routing.RuleStore.list(EsrDomainChat.Routing.MentionRouting)

    matched =
      Enum.any?(rules, fn row ->
        URI.to_string(feishu_uri) in row.receivers and
          row.matcher_data == Esr.Routing.Matcher.to_json(Esr.Routing.Matcher.in_session(session_uri))
      end)

    assert matched, "expected MentionRouting to contain an in_session(#{session_uri_str}) → [#{URI.to_string(feishu_uri)}] rule; got: #{inspect(rules)}"

    # Idempotent re-instantiate
    assert {:ok, [^feishu_uri]} =
             FeishuChatBinding.instantiate(
               "main",
               %{"session_uri" => session_uri_str, "chat_id" => chat_id},
               URI.parse("workspace://test")
             )

    # Still one rule, not two
    rules_after = Esr.Routing.RuleStore.list(EsrDomainChat.Routing.MentionRouting)
    count = Enum.count(rules_after, &(URI.to_string(feishu_uri) in &1.receivers))
    assert count == 1, "expected 1 feishu rule after re-instantiate; got #{count}"
  end

  test "form_fields declares session_uri + chat_id" do
    fields = FeishuChatBinding.form_fields()
    names = Enum.map(fields, & &1.name)
    assert "session_uri" in names
    assert "chat_id" in names
  end

  test "FeishuChat Kind type_name + uri_for + chat_id_from_uri" do
    assert Esr.Entity.FeishuChat.type_name() == :feishu_chat
    uri = Esr.Entity.FeishuChat.uri_for("oc_xyz")
    assert URI.to_string(uri) == "feishu://oc_xyz"
    assert Esr.Entity.FeishuChat.chat_id_from_uri(uri) == "oc_xyz"
  end
end
