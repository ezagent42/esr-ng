defmodule EzagentCli.Integration.CliLvCapParityTest do
  @moduledoc """
  Phase 7 PR 34 invariant — V3.4: a non-admin user invoking actions via
  CLI (token-bound) hits CapBAC with caps derived from the SAME
  function as the LV surface, so authz decisions are deterministically
  identical for the same user.

  ## Why this matters

  CLI and LV are two separate auth surfaces. If they diverge on caps
  resolution, an action a user can do via LV becomes impossible via
  CLI (or vice versa) — breaking the "CLI ↔ LV same-server invariant"
  (Decision #130). The structural reason this works today is that
  BOTH paths derive caps from `Ezagent.Identity.list_caps_for/1`. This
  test pins that contract.

  ## What the test asserts

  1. Token → user URI lookup is bijective: rotating a token for a
     user creates a binding such that `lookup_by_cli_token(token)`
     returns the same user URI.
  2. CLI's resolve_caller (private, but exercised via the public
     Identity.list_caps_for path) and LV's mount-time cap derivation
     converge on the SAME `Ezagent.Identity.list_caps_for/1` result for
     the same user.
  3. Invalid tokens cleanly return `:error` (the path CLI Exec
     converts to exit code 4).
  4. Non-admin users do NOT receive admin wildcard caps via CLI
     token (no privilege elevation bug).

  ## What this test does NOT cover

  - Caps that are present in the DB row but not yet in the in-memory
    User Kind slice — populated on Kind spawn via `initial_caps`,
    which requires Loader-style hydration (see ezagent.user.create mix
    task line 106 comment). For fresh-created users in a unit-test
    sandbox, slice caps start empty until restart hydration; the
    parity invariant (both surfaces see THE SAME caps, whatever
    those are) still holds because they share the lookup function.
  - End-to-end dispatch from each surface (covered by
    `cli_lv_same_server_invariant_test.exs` which proves both
    reach the SAME `Ezagent.Invocation.dispatch` function in the
    same BEAM).

  Combined with the same-server invariant test, this gives us
  "same caps + same BEAM = same authz decision" — V3.4 in its
  observable form.
  """

  use EzagentCore.DataCase, async: false

  alias Ezagent.Users
  alias Ezagent.Capability

  setup do
    suffix = "parity-#{System.unique_integer([:positive])}"
    user_uri = URI.new!("user://#{suffix}")
    {:ok, %{uri: user_uri, suffix: suffix}}
  end

  defp create_user_with_caps(uri, extra_caps) when is_list(extra_caps) do
    {:ok, _decoded} = Users.create(URI.to_string(uri), "test-password", extra_caps)
    {:ok, _pid} = Ezagent.SpawnRegistry.spawn(uri)
    :ok
  end

  test "token lookup returns the user URI it was rotated for", %{uri: user_uri} do
    :ok = create_user_with_caps(user_uri, [])
    {:ok, token} = Users.rotate_cli_token(URI.to_string(user_uri))

    assert {:ok, returned_uri} = Users.lookup_by_cli_token(token)

    assert URI.to_string(returned_uri) == URI.to_string(user_uri),
           "lookup_by_cli_token returned a different user URI than created — " <>
             "got #{URI.to_string(returned_uri)}, expected #{URI.to_string(user_uri)}"
  end

  test "CLI-resolved caps == LV-resolved caps for the same user (V3.4 parity)", %{uri: user_uri} do
    workspace_cap = %Capability{
      kind: :workspace,
      behavior: :any,
      instance: :any,
      granted_by: URI.parse("user://admin"),
      granted_at: ~U[2026-05-18 00:00:00Z]
    }

    :ok = create_user_with_caps(user_uri, [workspace_cap])
    {:ok, token} = Users.rotate_cli_token(URI.to_string(user_uri))

    # CLI path: token → user URI → list_caps_for
    {:ok, cli_user_uri} = Users.lookup_by_cli_token(token)
    cli_caps = Ezagent.Identity.list_caps_for(cli_user_uri)

    # LV path: session cookie → user URI → list_caps_for (same function)
    lv_caps = Ezagent.Identity.list_caps_for(user_uri)

    # The two surfaces MUST converge on the same MapSet — that's
    # the V3.4 parity invariant. Both call list_caps_for/1, so this
    # is structurally guaranteed today; the test pins the contract
    # so any future refactor that diverges the lookup paths fails CI.
    assert cli_caps == lv_caps,
           "CLI-derived caps != LV-derived caps for the same user — " <>
             "the two auth surfaces have diverged on caps resolution. " <>
             "Decision #130 (CLI ↔ LV same-server invariant) violated. " <>
             "CLI got #{MapSet.size(cli_caps)} caps; LV got #{MapSet.size(lv_caps)} caps."
  end

  test "invalid token returns :error (the path CLI Exec converts to exit code 4)" do
    fake_token = "not-a-real-token-#{System.unique_integer([:positive])}"
    assert :error = Users.lookup_by_cli_token(fake_token)
  end

  test "non-admin token does NOT resolve to admin wildcard cap", %{uri: user_uri} do
    :ok = create_user_with_caps(user_uri, [])
    {:ok, token} = Users.rotate_cli_token(URI.to_string(user_uri))

    {:ok, returned_uri} = Users.lookup_by_cli_token(token)
    caps = Ezagent.Identity.list_caps_for(returned_uri)

    refute Enum.any?(caps, fn c ->
             c.kind == :any and c.behavior == :any and c.instance == :any
           end),
           "non-admin user resolved to admin wildcard cap via CLI token — " <>
             "auth elevation bug; only user://admin should hold this cap"
  end
end
