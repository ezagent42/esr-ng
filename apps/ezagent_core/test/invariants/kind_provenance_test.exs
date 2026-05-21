defmodule Ezagent.Invariants.KindProvenanceTest do
  @moduledoc """
  Asserts every alive Kind in `Ezagent.KindRegistry` has its pid
  supervised by one of the declared Kind supervisors. Catches future
  "spawned outside `Ezagent.Kind.spawn/2`" drift at runtime, even if
  the grep gate is somehow bypassed (e.g. by `apply/3` or a string
  build).

  Per V1 prevention layer 2 (Allen 2026-05-21): runtime invariant
  that drift cannot hide. If a Kind appears in KindRegistry but no
  declared supervisor owns its pid, either the spawn went through an
  unknown path OR a new per-Kind supervisor needs to be added to
  `supervisors/0` below.

  The list is the union of every `supervisor/0` declared on a Kind
  module today, plus the default `Ezagent.KindSupervisor`. Tests
  reference Kinds across all umbrella apps so this runs in the
  ezagent_core test env where the full supervision tree boots.
  """
  use ExUnit.Case

  test "every alive Kind URI has a pid supervised by a declared Kind supervisor" do
    alive = Ezagent.KindRegistry.list_all()

    supervised_pids =
      supervisors()
      |> Enum.flat_map(fn sup ->
        case Process.whereis(sup) do
          nil ->
            []

          _pid ->
            DynamicSupervisor.which_children(sup)
        end
      end)
      |> Enum.map(fn {_id, pid, _type, _modules} -> pid end)
      |> MapSet.new()

    unsupervised =
      Enum.reject(alive, fn {_uri, pid} -> MapSet.member?(supervised_pids, pid) end)

    assert unsupervised == [],
           """
           Alive Kinds NOT under any declared Kind supervisor:

           #{Enum.map_join(unsupervised, "\n", fn {uri, pid} -> "  #{uri} (pid #{inspect(pid)})" end)}

           Kinds spawned outside Ezagent.Kind.spawn/2 are caught here.
           Either route the spawn through the API, or — if a new Kind
           declared its own DynamicSupervisor — add the supervisor module
           to supervisors/0 in this test.
           """
  end

  # Union of every `supervisor/0` declared on a Kind module + the
  # default. Adding a new per-Kind supervisor: append it here.
  defp supervisors do
    [
      Ezagent.KindSupervisor,
      Ezagent.Core.SingletonSupervisor,
      Ezagent.Workspace.Supervisor,
      EzagentDomainIdentity.Application.UserSupervisor,
      EzagentDomainChat.SessionSupervisor,
      EzagentDomainChat.AgentSupervisor,
      EzagentDomainChat.AgentTemplateSupervisor,
      EzagentDomainChat.SessionTemplateSupervisor,
      EzagentPluginCurlAgent.InstanceSupervisor
    ]
  end
end
