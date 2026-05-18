defmodule Esr.CapabilityTest do
  use ExUnit.Case, async: true
  alias Esr.Capability

  @user_uri URI.parse("user://alice")
  @system_uri URI.parse("system://bootstrap")
  @other_uri URI.parse("system://other")
  @now ~U[2026-05-15 00:00:00Z]

  describe "matches?/2" do
    test "exact match on all three fields" do
      cap = %Capability{
        kind: :echo,
        behavior: Esr.Behavior.Echo,
        instance: URI.parse("agent://echo"),
        granted_by: @user_uri,
        granted_at: @now
      }

      assert Capability.matches?(cap, %{
               kind: :echo,
               behavior: Esr.Behavior.Echo,
               instance: URI.parse("agent://echo")
             })
    end

    test ":any wildcard matches any kind" do
      cap = %Capability{
        kind: :any,
        behavior: Esr.Behavior.Echo,
        instance: URI.parse("agent://echo"),
        granted_by: @user_uri,
        granted_at: @now
      }

      assert Capability.matches?(cap, %{
               kind: :anything,
               behavior: Esr.Behavior.Echo,
               instance: URI.parse("agent://echo")
             })
    end

    test "triple-:any matches anything" do
      cap = %Capability{
        kind: :any,
        behavior: :any,
        instance: :any,
        granted_by: @user_uri,
        granted_at: @now
      }

      assert Capability.matches?(cap, %{
               kind: :random_kind,
               behavior: SomeMod,
               instance: URI.parse("agent://whatever")
             })
    end

    test "non-match on kind" do
      cap = %Capability{
        kind: :echo,
        behavior: :any,
        instance: :any,
        granted_by: @user_uri,
        granted_at: @now
      }

      refute Capability.matches?(cap, %{
               kind: :chat,
               behavior: Mod,
               instance: URI.parse("agent://x")
             })
    end
  end

  describe "revoke/2" do
    test "removes a non-admin cap" do
      cap = %Capability{
        kind: :echo,
        behavior: :any,
        instance: :any,
        granted_by: @user_uri,
        granted_at: @now
      }

      caps = MapSet.new([cap])
      assert {:ok, new_caps} = Capability.revoke(caps, cap)
      assert MapSet.size(new_caps) == 0
    end

    test "refuses to revoke admin all-caps invariant" do
      admin = %Capability{
        kind: :any,
        behavior: :any,
        instance: :any,
        granted_by: @system_uri,
        granted_at: @now
      }

      caps = MapSet.new([admin])
      assert {:error, :cannot_revoke_admin} = Capability.revoke(caps, admin)
    end

    test "triple-:any but granted by non-bootstrap is revokable" do
      # Edge: same shape as admin but granted by a normal user — that's
      # a delegated grant, not the structural invariant, so revokable.
      cap = %Capability{
        kind: :any,
        behavior: :any,
        instance: :any,
        granted_by: @other_uri,
        granted_at: @now
      }

      caps = MapSet.new([cap])
      assert {:ok, _new_caps} = Capability.revoke(caps, cap)
    end
  end

  describe "cap_for_action/3 (Phase 3d)" do
    test "extracts kind type name + behavior from registry + instance from URI" do
      # Echo plugin pre-registers BehaviorRegistry at boot
      target = URI.new!("agent://echo/behavior/echo/say")

      needed = Capability.cap_for_action(Esr.Entity.Echo, :say, target)

      assert needed.kind == :echo
      assert needed.behavior == Esr.Behavior.Echo
      assert needed.instance == URI.new!("agent://echo")
    end

    test "unknown action returns :unknown behavior" do
      target = URI.new!("agent://echo/behavior/echo/say")
      needed = Capability.cap_for_action(Esr.Entity.Echo, :nonexistent_action, target)
      assert needed.behavior == :unknown
    end

    test "session://main/behavior/chat/send → :session + Chat + session://main instance" do
      target = URI.new!("session://main/behavior/chat/send")
      needed = Capability.cap_for_action(Esr.Entity.Session, :send, target)

      assert needed.kind == :session
      assert needed.behavior == Esr.Behavior.Chat
      assert needed.instance == URI.new!("session://main")
    end

    test "admin all-cap matches the needed shape (closed-loop integration)" do
      [admin_cap] = MapSet.to_list(Esr.Entity.User.admin_caps())
      target = URI.new!("session://main/behavior/chat/send")
      needed = Capability.cap_for_action(Esr.Entity.Session, :send, target)

      assert Capability.matches?(admin_cap, needed)
    end
  end

  describe "scope-bounded instance tuples (Phase 7 PR 42 / D7-3)" do
    defp scoped_cap(instance) do
      %Capability{
        kind: :session,
        behavior: :any,
        instance: instance,
        granted_by: URI.parse("user://admin"),
        granted_at: ~U[2026-05-18 00:00:00Z]
      }
    end

    defp needed(target_str) do
      target = URI.new!(target_str)
      Capability.cap_for_action(Esr.Entity.Session, :send, target)
    end

    test "{:within_session, S} matches needed targeting URI exactly equal to S" do
      cap = scoped_cap({:within_session, URI.new!("session://main")})
      assert Capability.matches?(cap, needed("session://main/behavior/chat/send"))
    end

    test "{:within_session, S} matches needed whose instance is a sub-URI of S (path prefix)" do
      cap = scoped_cap({:within_session, URI.new!("session://main")})

      needed_subpath = %{
        kind: :session,
        behavior: :any,
        instance: URI.parse("session://main/sub-path")
      }

      assert Capability.matches?(cap, needed_subpath)
    end

    test "{:within_session, S} does NOT match needed in a different session (V3.2 scope leak)" do
      cap = scoped_cap({:within_session, URI.new!("session://main")})
      refute Capability.matches?(cap, needed("session://other/behavior/chat/send"))
    end

    test "{:within_session, session://main} does NOT false-match session://main2 (prefix boundary)" do
      cap = scoped_cap({:within_session, URI.new!("session://main")})

      needed_neighbor = %{
        kind: :session,
        behavior: :any,
        instance: URI.parse("session://main2")
      }

      refute Capability.matches?(cap, needed_neighbor),
             "{:within_session, session://main} must not match session://main2 — " <>
               "prefix check requires '/' boundary, not raw startsWith"
    end

    test "{:spawned_by, P} with no lineage recorded denies (deny-when-absent)" do
      # PR 40 ships Esr.AgentLineage registry; without a recorded
      # spawn relationship, the cap denies. This is the new
      # placeholder-equivalent (was hard-coded false in PR 42; now
      # ETS lookup that's empty).
      cap = scoped_cap({:spawned_by, URI.new!("agent://orchestrator-unrecorded")})

      needed_any_agent = %{
        kind: :agent,
        behavior: :any,
        instance: URI.parse("agent://worker-no-lineage-#{System.unique_integer([:positive])}")
      }

      refute Capability.matches?(cap, needed_any_agent),
             "{:spawned_by, _} cap must deny when AgentLineage has no record " <>
               "of the spawn relationship — deny-when-absent is the conservative default"
    end

    test "{:spawned_by, P} matches when lineage IS recorded (PR 40 real impl)" do
      orchestrator = URI.new!("agent://orchestrator-#{System.unique_integer([:positive])}")
      worker = URI.new!("agent://worker-#{System.unique_integer([:positive])}")

      :ok = Esr.AgentLineage.record(worker, orchestrator)

      # Sanity: verify the record landed (catches scope_cap kind
      # mismatch or test sandbox confusion before we blame the
      # matches? code).
      assert {:ok, returned} = Esr.AgentLineage.lookup(worker)

      assert URI.to_string(returned) == URI.to_string(orchestrator),
             "AgentLineage.lookup returned wrong orchestrator URI"

      assert Esr.AgentLineage.spawned_in_lineage?(worker, orchestrator),
             "AgentLineage.spawned_in_lineage? returned false despite the record"

      cap = %Capability{
        kind: :agent,
        behavior: :any,
        instance: {:spawned_by, orchestrator},
        granted_by: URI.parse("user://admin"),
        granted_at: ~U[2026-05-18 00:00:00Z]
      }

      needed_worker = %{
        kind: :agent,
        behavior: :any,
        instance: worker
      }

      assert Capability.matches?(cap, needed_worker),
             "{:spawned_by, orchestrator} cap must match when worker was recorded as " <>
               "spawned by orchestrator (PR 40 real lineage impl)"

      # Clean up so this test doesn't leak ETS state to other tests
      Esr.AgentLineage.forget(worker)
    end

    test "{:spawned_by, P} does NOT match an unrelated agent (lineage isolation)" do
      orchestrator_a = URI.new!("agent://orch-a-#{System.unique_integer([:positive])}")
      orchestrator_b = URI.new!("agent://orch-b-#{System.unique_integer([:positive])}")
      worker_of_a = URI.new!("agent://worker-of-a-#{System.unique_integer([:positive])}")

      :ok = Esr.AgentLineage.record(worker_of_a, orchestrator_a)

      cap_for_b = %Capability{
        kind: :agent,
        behavior: :any,
        instance: {:spawned_by, orchestrator_b},
        granted_by: URI.parse("user://admin"),
        granted_at: ~U[2026-05-18 00:00:00Z]
      }

      needed_worker_of_a = %{
        kind: :agent,
        behavior: :any,
        instance: worker_of_a
      }

      refute Capability.matches?(cap_for_b, needed_worker_of_a),
             "orchestrator B's {:spawned_by, B} cap must NOT match a worker spawned by " <>
               "orchestrator A — lineage isolation prevents cross-orchestrator authority"

      Esr.AgentLineage.forget(worker_of_a)
    end

    test "scope tuple cap with wrong kind does NOT match (scope only narrows, never broadens)" do
      cap = %Capability{
        kind: :workspace,
        behavior: :any,
        instance: {:within_session, URI.new!("session://main")},
        granted_by: URI.parse("user://admin"),
        granted_at: ~U[2026-05-18 00:00:00Z]
      }

      refute Capability.matches?(cap, needed("session://main/behavior/chat/send")),
             "scope-tuple cap with wrong kind must NOT match"
    end
  end
end
