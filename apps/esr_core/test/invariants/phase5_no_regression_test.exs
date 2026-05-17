defmodule EsrCore.Invariants.Phase5NoRegressionTest do
  @moduledoc """
  Phase 6 PR 12 closeout invariant — pins Phase 5 functionality that
  MUST NOT regress through any Phase 6+ refactor.

  Per Allen's directive: "确保和 phase 5 时的功能没有回归".

  Each test names the Phase 5 capability it's pinning. If a Phase 6 PR
  breaks one of these, the assertion failure is the signal.

  Scope deliberately covers core surfaces only — full e2e (Feishu /
  CC channel) lives in agent-browser tests + manual demo.
  """
  use ExUnit.Case, async: false

  alias Esr.{BehaviorRegistry, KindRegistry, RoutingRegistry}

  describe "Phase 5: foundational Kinds" do
    test "session://main is registered" do
      uri = Esr.Entity.Session.default_uri()
      assert {:ok, pid} = KindRegistry.lookup(uri)
      assert Process.alive?(pid)
    end

    test "user://admin is registered + has admin caps" do
      uri = Esr.Entity.User.admin_uri()
      assert {:ok, pid} = KindRegistry.lookup(uri)
      assert Process.alive?(pid)

      # Admin must carry the global admin cap set so admin LV can do anything.
      caps = Esr.Entity.User.admin_caps()
      assert MapSet.size(caps) > 0
    end

    test "routing-admin://default singleton is alive" do
      uri = Esr.Entity.RoutingAdmin.default_uri()
      assert {:ok, pid} = KindRegistry.lookup(uri)
      assert Process.alive?(pid)
    end
  end

  describe "Phase 5: BehaviorRegistry wiring" do
    test "Chat actions are registered on the right Kinds" do
      # Session-side actions
      assert {:ok, Esr.Behavior.Chat} =
               BehaviorRegistry.lookup(Esr.Entity.Session, :send)

      assert {:ok, Esr.Behavior.Chat} =
               BehaviorRegistry.lookup(Esr.Entity.Session, :join)

      assert {:ok, Esr.Behavior.Chat} =
               BehaviorRegistry.lookup(Esr.Entity.Session, :leave)

      # Receiver-side
      assert {:ok, Esr.Behavior.Chat} =
               BehaviorRegistry.lookup(Esr.Entity.User, :receive)

      assert {:ok, Esr.Behavior.Chat} =
               BehaviorRegistry.lookup(Esr.Entity.Agent, :receive)
    end

    test "Identity actions are registered" do
      assert {:ok, Esr.Behavior.Identity} =
               BehaviorRegistry.lookup(Esr.Entity.User, :list_caps)

      assert {:ok, Esr.Behavior.Identity} =
               BehaviorRegistry.lookup(Esr.Entity.User, :has_cap?)
    end

    test "Workspace actions are registered" do
      actions = Esr.Behavior.Workspace.actions()
      assert length(actions) > 0

      for action <- actions do
        assert {:ok, Esr.Behavior.Workspace} =
                 BehaviorRegistry.lookup(Esr.Entity.Workspace, action)
      end
    end
  end

  describe "Phase 5: routing tables declared" do
    test "MentionRouting + SessionRouting tables exist" do
      assert :ets.whereis(:"esr_routing_Elixir.EsrDomainChat.Routing.MentionRouting") !=
               :undefined

      assert :ets.whereis(:"esr_routing_Elixir.EsrDomainChat.Routing.SessionRouting") !=
               :undefined
    end

    test "default $session_members rule is loaded" do
      # The boot path loads the system_default rule that fan-outs to
      # session members. Without this, chat/send routes nowhere.
      entries = RoutingRegistry.list_all(EsrDomainChat.Routing.MentionRouting)

      assert Enum.any?(entries, fn {_matcher, value} ->
               receivers =
                 case value do
                   list when is_list(list) -> list
                   %{receivers: r} -> r
                 end

               "$session_members" in receivers
             end),
             "system_default $session_members rule missing from MentionRouting"
    end
  end

  describe "Phase 5: ESR_HOME runtime persistence" do
    test "Esr.Home resolves to a non-empty path" do
      assert is_binary(Esr.Home.home())
      assert Esr.Home.home() != ""
      assert is_binary(Esr.Home.profile())
    end
  end

  describe "Phase 5: distributed Erlang runtime configured (boot path)" do
    test "Esr.Runtime exposes runtime_node + cookie_path" do
      assert is_atom(Esr.Runtime.runtime_node())
      assert is_binary(Esr.Runtime.cookie_path())
    end
  end
end
