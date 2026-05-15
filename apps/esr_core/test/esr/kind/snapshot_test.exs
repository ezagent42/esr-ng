defmodule Esr.Kind.SnapshotTest do
  use ExUnit.Case
  alias Esr.Kind.Snapshot
  alias Esr.Test.TestKind

  test "load_or_init for :ephemeral returns fresh slices" do
    uri = URI.parse("agent://snap-eph-#{System.unique_integer([:positive])}")
    state = Snapshot.load_or_init(uri, TestKind, %{uri: uri})

    # TestKind has one behavior (TestBehavior) with state_slice :test
    # and init_slice returning %{count: 0, last_msg: nil}.
    assert state == %{test: %{count: 0, last_msg: nil}}
  end

  test "load_or_init for :on_change Kind without prior snapshot also init_fresh" do
    # Esr.Entity.User has persistence {:snapshot, :on_change}, no
    # Behaviors. Phase 1 snapshot fetch always misses, so we still
    # get an empty initial state.
    uri = Esr.Entity.User.admin_uri()
    assert %{} == Snapshot.load_or_init(uri, Esr.Entity.User, %{uri: uri})
  end

  test "maybe_save no-op for :ephemeral" do
    uri = URI.parse("agent://snap-eph-#{System.unique_integer([:positive])}")
    assert :ok = Snapshot.maybe_save(uri, TestKind, %{}, %{test: %{count: 1}})
  end

  test "maybe_save no-op for unchanged on_change Kind" do
    state = %{}
    uri = Esr.Entity.User.admin_uri()
    assert :ok = Snapshot.maybe_save(uri, Esr.Entity.User, state, state)
  end

  test "maybe_save emits :save_skipped_phase1 telemetry when changed" do
    # Phase 1 skeleton emits a marker so the call-site is observable
    # even though no SQLite write happens yet.
    test_pid = self()
    ref = make_ref()
    handler_id = "snap-test-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler_id,
      [:esr, :persistence, :save_skipped_phase1],
      fn _e, _m, _meta, _config -> send(test_pid, {ref, :seen}) end,
      nil
    )

    uri = Esr.Entity.User.admin_uri()
    assert :ok = Snapshot.maybe_save(uri, Esr.Entity.User, %{}, %{x: 1})

    assert_receive {^ref, :seen}, 500
    :telemetry.detach(handler_id)
  end
end
