defmodule EzagentPluginFeishu.SessionBindingTest do
  @moduledoc """
  PR #144 SPEC v2 §5.8 — chat_id ↔ session_uri storage.
  """
  use EzagentCore.DataCase, async: false

  alias EzagentPluginFeishu.SessionBinding

  test "bind then resolve" do
    chat_id = "oc_sb_#{System.unique_integer([:positive])}"
    session_uri = "session://default/default/sb-#{System.unique_integer([:positive])}"

    assert {:ok, _row} = SessionBinding.bind(chat_id, session_uri)
    assert {:ok, %URI{} = uri} = SessionBinding.resolve(chat_id)
    assert URI.to_string(uri) == session_uri
  end

  test "resolve returns :error for unbound / disabled / invalid" do
    assert :error = SessionBinding.resolve("oc_does_not_exist_xyz")
    assert :error = SessionBinding.resolve(nil)
    assert :error = SessionBinding.resolve("")
  end

  test "rebind replaces session_uri silently" do
    chat_id = "oc_rebind_#{System.unique_integer([:positive])}"
    {:ok, _} = SessionBinding.bind(chat_id, "session://default/default/first")
    {:ok, _} = SessionBinding.bind(chat_id, "session://default/default/second")

    {:ok, uri} = SessionBinding.resolve(chat_id)
    assert URI.to_string(uri) == "session://default/default/second"
  end

  test "chat_ids_for returns all enabled chat_ids for a session" do
    session = "session://default/default/multi_#{System.unique_integer([:positive])}"
    {:ok, _} = SessionBinding.bind("oc_a_#{System.unique_integer([:positive])}", session)
    {:ok, _} = SessionBinding.bind("oc_b_#{System.unique_integer([:positive])}", session)

    chat_ids = SessionBinding.chat_ids_for(session)
    assert length(chat_ids) == 2
  end

  test "unbind removes the row" do
    chat_id = "oc_unbind_#{System.unique_integer([:positive])}"
    {:ok, _} = SessionBinding.bind(chat_id, "session://default/default/x")
    assert :ok = SessionBinding.unbind(chat_id)
    assert :error = SessionBinding.resolve(chat_id)
  end

  test "unbind on unknown returns :not_found" do
    assert {:error, :not_found} = SessionBinding.unbind("oc_never_bound_xyz")
  end
end
