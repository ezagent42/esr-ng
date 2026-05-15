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
end
