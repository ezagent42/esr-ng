defmodule EsrPluginFeishu.SenderResolverTest do
  @moduledoc """
  Phase 6 PR 15 — SenderResolver maps Feishu sender → ESR caller+caps.
  """
  use EsrCore.DataCase, async: false

  alias EsrPluginFeishu.{SenderResolver, UserBinding}

  test "bound open_id resolves to caller URI" do
    open_id = "ou_resolver_test_#{System.unique_integer([:positive])}"
    user_uri = "user://resolver_test_#{System.unique_integer([:positive])}"
    {:ok, _} = UserBinding.bind(open_id, user_uri, "user://admin")

    sender = %{"sender_id" => %{"open_id" => open_id}}
    assert {:ok, %URI{} = caller, _caps} = SenderResolver.resolve(sender)
    assert URI.to_string(caller) == user_uri
  end

  test "unbound open_id returns :pending" do
    sender = %{"sender_id" => %{"open_id" => "ou_never_seen_xyz"}}
    assert {:pending, "ou_never_seen_xyz"} = SenderResolver.resolve(sender)
  end

  test "user_id (not open_id) returns :pending with prefix" do
    sender = %{"sender_id" => %{"user_id" => "u_abc"}}
    assert {:pending, "user_id:u_abc"} = SenderResolver.resolve(sender)
  end

  test "malformed sender returns error" do
    assert {:error, :bad_sender} = SenderResolver.resolve(%{"junk" => 1})
  end
end
