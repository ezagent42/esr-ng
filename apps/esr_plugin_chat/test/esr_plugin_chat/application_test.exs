defmodule EsrPluginChat.ApplicationTest do
  @moduledoc """
  Phase 2b-step 1: boot integration — verify the three children land in
  their expected runtime state after the umbrella starts.

  These assertions run against the live KindRegistry / DynamicSupervisor
  populated at application boot — not test-spawned fixtures. The Phase 1
  echo plugin uses the same pattern (its boot spawns `agent://echo` and
  tests assert on the live registry entry).
  """

  use ExUnit.Case
  alias Esr.{KindRegistry, ReadyGate}

  test "session://main is registered in KindRegistry" do
    uri = Esr.Entity.Session.default_uri()
    assert {:ok, pid} = KindRegistry.lookup(uri)
    assert Process.alive?(pid)
  end

  test "session://main is marked :ready in ReadyGate" do
    uri_str = URI.to_string(Esr.Entity.Session.default_uri())
    assert :ready = ReadyGate.status(uri_str)
  end

  test "user://admin is registered in KindRegistry" do
    uri = Esr.Entity.User.admin_uri()
    assert {:ok, pid} = KindRegistry.lookup(uri)
    assert Process.alive?(pid)
  end

  test "user://admin is marked :ready in ReadyGate" do
    uri_str = URI.to_string(Esr.Entity.User.admin_uri())
    assert :ready = ReadyGate.status(uri_str)
  end

  test "AgentSupervisor is alive with zero children (agents spawn on bridge announce)" do
    sup = Process.whereis(EsrPluginChat.AgentSupervisor)
    assert is_pid(sup) and Process.alive?(sup)

    assert %{active: 0, specs: 0, workers: 0} = DynamicSupervisor.count_children(sup)
  end
end
