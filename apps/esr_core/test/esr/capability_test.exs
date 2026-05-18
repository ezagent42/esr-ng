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

    test "{:spawned_by, P} placeholder returns false until PR 40 ships lineage (deny-by-default)" do
      cap = scoped_cap({:spawned_by, URI.new!("agent://orchestrator-1")})

      needed_any_agent = %{
        kind: :agent,
        behavior: :any,
        instance: URI.parse("agent://worker-spawned-by-orchestrator-1")
      }

      refute Capability.matches?(cap, needed_any_agent),
             "PR 42 ships {:spawned_by, _} as deny-by-default placeholder; " <>
               "PR 40 lineage registry will flip this to a real match. " <>
               "Until then, deny is the conservative correct answer."
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
