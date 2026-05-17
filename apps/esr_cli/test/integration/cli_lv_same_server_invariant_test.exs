defmodule EsrCLI.Integration.CliLvSameServerInvariantTest do
  @moduledoc """
  Post-Phase-5 invariant (Allen 2026-05-17): CLI and LV must reach the
  SAME BEAM. Previously `mix esr` started its own VM and the dispatch
  hit isolated state — LV couldn't see CLI mutations. That was a real
  drift.

  Fix: `Mix.Tasks.Esr` is now a thin HTTP shell over `/api/cli/exec`;
  the server-side `EsrCLI.Exec.exec(argv)` runs in the RUNNING server
  BEAM.

  This test pins the invariant by:
  1. Spawning a Session Kind in THIS test process's BEAM
  2. Calling `EsrCLI.Exec.exec(["session", "join", ...])` directly
     (server-side path — same as what /api/cli/exec invokes)
  3. Asserting the Session GenServer's state changed in THIS BEAM
     (member list now contains the joined member)

  If a future refactor moves CLI back to spawning its own VM, the
  member assertion will FAIL because the join happens in a separate
  process tree from the one this test inspects.
  """
  use ExUnit.Case, async: false

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(EsrCore.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(EsrCore.Repo, {:shared, self()})
    :ok
  end

  test "CLI server-side exec changes Session.chat.members IN THIS BEAM" do
    session_name = "cli-same-server-test-#{System.unique_integer([:positive])}"
    session_uri = URI.parse("session://" <> session_name)
    member_uri = URI.parse("agent://cli-test-member-#{System.unique_integer([:positive])}")

    # Spawn session in this BEAM
    {:ok, session_pid} = Esr.SpawnRegistry.spawn(session_uri)
    Process.sleep(50)

    # Spawn the agent so chat/join's lookup succeeds
    {:ok, _agent_pid} = Esr.SpawnRegistry.spawn(member_uri)
    Process.sleep(50)

    member_uri_str = URI.to_string(member_uri)

    # Confirm member is NOT there yet (compare by URI string to dodge
    # %URI{authority: ...} vs host-only equality quirk)
    state_before = :sys.get_state(session_pid, 500)

    refute Enum.any?(Map.keys(state_before.state.chat.members), fn k ->
             URI.to_string(k) == member_uri_str
           end)

    # Call CLI server-side path (what /api/cli/exec does)
    result =
      EsrCLI.Exec.exec([
        "session",
        "join",
        "--session",
        session_name,
        "--member",
        URI.to_string(member_uri),
        "--cast"
      ])

    assert result.exit_code == 0,
           "CLI exec returned non-zero: output=#{inspect(result.output)} exit=#{result.exit_code}"

    # Give cast some time to land
    Process.sleep(100)

    # Confirm member NOW IS in the SAME GenServer this test spawned —
    # proves the CLI exec ran in the same BEAM, not a separate VM
    state_after = :sys.get_state(session_pid, 500)

    member_present? =
      Enum.any?(Map.keys(state_after.state.chat.members), fn k ->
        URI.to_string(k) == member_uri_str
      end)

    assert member_present?, """
    CLI exec completed (exit 0) but member #{member_uri_str} is NOT in the
    Session GenServer this test holds a pid for.

    Means CLI dispatched against a DIFFERENT BEAM than the test — breaks
    CLI ↔ LV isomorphism.

    Members in this BEAM: #{inspect(Enum.map(Map.keys(state_after.state.chat.members), &URI.to_string/1))}
    """
  end

  test "CLI exec returns formatted output + correct exit code" do
    # Help path: no args
    result = EsrCLI.Exec.exec([])
    assert is_map(result)
    assert is_binary(result.output)
    assert result.exit_code == 0
    assert result.output =~ "ESR Invocation CLI"
  end

  test "CLI exec for unknown subcommand returns non-zero exit" do
    result = EsrCLI.Exec.exec(["totally_nonexistent_kind"])
    assert result.exit_code != 0
  end
end
