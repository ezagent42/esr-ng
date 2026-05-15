defmodule EsrPluginChat.Application do
  @moduledoc """
  Chat plugin OTP application.

  ## Phase 2a scope (this commit)

  Application declaration only — no children, no BehaviorRegistry
  registration. The Chat Behavior contract (`Esr.Behavior.Chat`) is
  declared in `lib/esr/behavior/chat.ex` with `invoke/4` clauses
  returning `{:error, :not_implemented_in_2a}` as stubs.

  Registration + supervisor wiring lands in **2b-step 1** along with
  Session/User/Agent Kinds. Per-Kind subset registration (Decision
  P2-D2 K-path):

      # Session Kind handles outbound:
      Esr.BehaviorRegistry.register(Esr.Entity.Session, :send, Esr.Behavior.Chat)
      Esr.BehaviorRegistry.register(Esr.Entity.Session, :join, Esr.Behavior.Chat)
      Esr.BehaviorRegistry.register(Esr.Entity.Session, :leave, Esr.Behavior.Chat)

      # User + Agent Kinds handle inbound:
      Esr.BehaviorRegistry.register(Esr.Entity.User, :receive, Esr.Behavior.Chat)
      Esr.BehaviorRegistry.register(Esr.Entity.Agent, :receive, Esr.Behavior.Chat)

  ## Why a separate plugin

  Chat is plugin-isolated per the north-star feedback rule
  (`feedback_north_star_plugin_isolation`) — future devs adding a
  different room-style Behavior (e.g. voice rooms, file rooms) should
  be able to plug it in without touching `esr_core`. The Session Kind
  itself lives in `esr_core` (kind machinery is core); the Behaviors
  that compose into it live in plugins.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = []
    Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__)
  end
end
