defmodule Ezagent.Users.CliTokenTest do
  @moduledoc """
  Phase 6 PR 7 — per-user CLI bearer token coverage.
  """
  use EzagentCore.DataCase, async: false

  alias Ezagent.Users

  setup do
    uri = "user://cli-token-test-#{System.unique_integer([:positive])}"
    {:ok, _} = Users.create(uri, "p@ss", [])
    {:ok, uri: uri}
  end

  test "rotate produces a token + lookup returns the user", %{uri: uri} do
    {:ok, token} = Users.rotate_cli_token(uri)

    assert String.starts_with?(token, "esr_pat_")
    # Base64 url-safe of 32 bytes = 43 chars + prefix length
    assert byte_size(token) > 40

    assert {:ok, parsed} = Users.lookup_by_cli_token(token)
    assert URI.to_string(parsed) == uri
  end

  test "rotate again invalidates the previous token", %{uri: uri} do
    {:ok, t1} = Users.rotate_cli_token(uri)
    {:ok, t2} = Users.rotate_cli_token(uri)

    assert t1 != t2
    assert :error = Users.lookup_by_cli_token(t1)
    assert {:ok, _} = Users.lookup_by_cli_token(t2)
  end

  test "revoke clears the token", %{uri: uri} do
    {:ok, t} = Users.rotate_cli_token(uri)
    assert :ok = Users.revoke_cli_token(uri)
    assert :error = Users.lookup_by_cli_token(t)
  end

  test "rotate on unknown user returns :not_found" do
    assert {:error, :not_found} = Users.rotate_cli_token("user://nope")
  end

  test "lookup with empty / nil / random string returns :error" do
    assert :error = Users.lookup_by_cli_token("")
    assert :error = Users.lookup_by_cli_token(nil)
    assert :error = Users.lookup_by_cli_token("not_a_token")
  end
end
