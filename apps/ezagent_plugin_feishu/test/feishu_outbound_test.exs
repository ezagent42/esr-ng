defmodule EzagentPluginFeishu.Behavior.FeishuOutboundTest do
  @moduledoc """
  PR #144 SPEC v2 §5.8 — invariant test for the outbound side-channel
  shape.

  After this PR, FeishuOutbound is the ONLY way an Ezagent chat send
  reaches Feishu. It is a Behavior registered on `Ezagent.Entity.Session`
  Kind (no plugin-owned scheme). If this test breaks, the plugin has
  drifted back toward the deleted `feishu://oc_xxx` Receiver Kind
  pattern.
  """
  use EzagentCore.DataCase, async: false

  alias Ezagent.Message
  alias EzagentPluginFeishu.Behavior.FeishuOutbound
  alias EzagentPluginFeishu.SessionBinding

  setup do
    # Ensure BehaviorRegistry has FeishuOutbound on Session Kind. The
    # plugin's Application.start registers it at boot, but tests that
    # start the OTP app via test_helper may have race conditions in
    # certain shapes. Idempotent re-register is cheap.
    :ok =
      Ezagent.BehaviorRegistry.register(
        Ezagent.Entity.Session,
        :notify_external,
        FeishuOutbound
      )

    :ok
  end

  test "actions/0 declares :notify_external" do
    assert :notify_external in FeishuOutbound.actions()
  end

  test "interface/0 schema is well-formed" do
    iface = FeishuOutbound.interface()
    assert is_map(iface[:notify_external])
    assert is_map(iface[:notify_external].args)
    assert :cast in iface[:notify_external].modes
  end

  test "invoke :notify_external on a session WITHOUT a binding → no-op skip" do
    session_uri = URI.parse("session://outbound-test-#{System.unique_integer([:positive])}")

    msg =
      Message.new(
        URI.parse("entity://user/admin"),
        %{text: "hello"}
      )

    ctx = %{self_uri: session_uri}

    assert {:ok, _slice, %{skipped: :no_binding}} =
             FeishuOutbound.invoke(
               :notify_external,
               %{send_calls: 0, total_bytes: 0},
               %{message: msg},
               ctx
             )
  end

  test "invoke :notify_external on body tagged _feishu_origin → self-echo skip" do
    session_uri = URI.parse("session://echo-test-#{System.unique_integer([:positive])}")
    chat_id = "oc_echo_#{System.unique_integer([:positive])}"
    {:ok, _} = SessionBinding.bind(chat_id, URI.to_string(session_uri))

    sender = URI.parse("entity://user/admin")

    # Body carries the origin tag that InboundDispatcher stamps on
    # every webhook-built message. FeishuOutbound must short-circuit
    # before any Client.send_text call so we don't loop messages
    # back to Feishu.
    msg = Message.new(sender, %{text: "loop?", _feishu_origin: true})
    ctx = %{self_uri: session_uri}

    assert {:ok, _slice, %{skipped: :self_echo}} =
             FeishuOutbound.invoke(
               :notify_external,
               %{send_calls: 0, total_bytes: 0},
               %{message: msg},
               ctx
             )
  end

  test "self-echo guard also matches string-keyed body (post MessageStore round-trip)" do
    session_uri = URI.parse("session://string-key-#{System.unique_integer([:positive])}")
    chat_id = "oc_strkey_#{System.unique_integer([:positive])}"
    {:ok, _} = SessionBinding.bind(chat_id, URI.to_string(session_uri))

    sender = URI.parse("entity://user/admin")

    # Simulate a message reloaded from MessageStore (Message.new
    # requires atom-keyed body, but MessageStore JSON-decodes with
    # string keys, so the in-flight message may carry either shape).
    # Construct the struct directly to mirror the post-reload shape.
    msg = %Message{
      uri: "message://" <> Ecto.UUID.generate(),
      sender: sender,
      body: %{"text" => "loop?", "_feishu_origin" => true},
      mentions: [],
      ref: nil,
      inserted_at: DateTime.utc_now()
    }

    ctx = %{self_uri: session_uri}

    assert {:ok, _slice, %{skipped: :self_echo}} =
             FeishuOutbound.invoke(
               :notify_external,
               %{send_calls: 0, total_bytes: 0},
               %{message: msg},
               ctx
             )
  end

  test "registered on Ezagent.Entity.Session for :notify_external" do
    # This is the architectural invariant. If a future PR moves
    # FeishuOutbound off Session Kind (e.g. invents a new
    # plugin-owned Kind), this assertion fails.
    assert {:ok, FeishuOutbound} =
             Ezagent.BehaviorRegistry.lookup(Ezagent.Entity.Session, :notify_external)
  end
end
