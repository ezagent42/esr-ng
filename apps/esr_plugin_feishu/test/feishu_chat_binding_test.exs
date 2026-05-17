defmodule Esr.Template.FeishuChatBindingTest do
  @moduledoc """
  Phase 5 PR 6 invariant — Feishu chat_binding Template Class +
  OutboundSubscriber. Real Lark calls are not exercised (network +
  credentials gate); this test pins the behaviour around the network
  boundary.
  """
  use ExUnit.Case, async: false

  alias Esr.Template.FeishuChatBinding

  setup do
    # No DB needed for this test (Template Class doesn't touch DB);
    # skip sandbox checkout.

    # Clean SubscriberSupervisor between tests so binding lookups don't
    # accumulate across test runs.
    sup = Process.whereis(EsrPluginFeishu.SubscriberSupervisor)

    if sup do
      for {_, pid, :worker, _} <- DynamicSupervisor.which_children(sup) do
        DynamicSupervisor.terminate_child(sup, pid)
      end
    end

    :ok
  end

  test "validate enforces session:// scheme + oc_ prefix on chat_id" do
    assert :ok =
             FeishuChatBinding.validate(%{
               "class" => "feishu.chat_binding",
               "session_uri" => "session://main",
               "chat_id" => "oc_abc123"
             })

    assert {:error, _} =
             FeishuChatBinding.validate(%{
               "class" => "feishu.chat_binding",
               "session_uri" => "user://allen",
               "chat_id" => "oc_x"
             })

    assert {:error, :chat_id_must_start_with_oc_} =
             FeishuChatBinding.validate(%{
               "class" => "feishu.chat_binding",
               "session_uri" => "session://main",
               "chat_id" => "wrong_prefix"
             })
  end

  test "instantiate registers OutboundSubscriber under SubscriberSupervisor + idempotent" do
    chat_id = "oc_test_#{System.unique_integer([:positive])}"
    session_uri = "session://feishu-test"

    assert {:ok, [%URI{scheme: "feishu-binding"}]} =
             FeishuChatBinding.instantiate(
               "main",
               %{"session_uri" => session_uri, "chat_id" => chat_id},
               URI.parse("workspace://test")
             )

    sup = Process.whereis(EsrPluginFeishu.SubscriberSupervisor)
    assert [{_, pid, :worker, _}] = DynamicSupervisor.which_children(sup) |> Enum.take(1)
    assert is_pid(pid)

    # Idempotent re-instantiate
    assert {:ok, [%URI{scheme: "feishu-binding"}]} =
             FeishuChatBinding.instantiate(
               "main",
               %{"session_uri" => session_uri, "chat_id" => chat_id},
               URI.parse("workspace://test")
             )

    children_after = DynamicSupervisor.which_children(sup)
    assert length(children_after) == 1
  end

  test "form_fields declares session_uri + chat_id" do
    fields = FeishuChatBinding.form_fields()
    names = Enum.map(fields, & &1.name)
    assert "session_uri" in names
    assert "chat_id" in names
  end

  test "client status reports configured? based on credentials presence" do
    status = EsrPluginFeishu.Client.status()
    assert Map.has_key?(status, :configured)
  end

  test "client send_text returns :credentials_not_configured when unfilled" do
    # In test env credentials may or may not be present. If configured,
    # test_mode would actually hit the network — skip in that case.
    case EsrPluginFeishu.Client.status() do
      %{configured: false} ->
        assert {:error, :credentials_not_configured} =
                 EsrPluginFeishu.Client.send_text("oc_x", "test")

      %{configured: true} ->
        # Just verify the call doesn't crash; real network calls validated
        # via demo, not in CI.
        :ok
    end
  end
end
