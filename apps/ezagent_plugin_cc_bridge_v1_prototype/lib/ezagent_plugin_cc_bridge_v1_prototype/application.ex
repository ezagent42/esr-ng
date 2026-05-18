defmodule EzagentPluginCcBridgeV1Prototype.Application do
  @moduledoc """
  v1_prototype CC bridge OTP application.

  Phase 1 spawns one bridge instance on boot. Phase 5's full
  ezagent_plugin_cc_channel will replace this with a DynamicSupervisor +
  multi-instance lifecycle. The _v1_prototype suffix throughout this
  app's directory + module names (per P1-D1) makes the Phase 5
  wholesale-replace boundary unambiguous.

  In test env we skip auto-spawning the bridge so tests can drive
  it manually with explicit script paths.
  """

  use Application

  @impl true
  def start(_type, _args) do
    # Rev 2026-05-15: Server is now a passive state tracker — it doesn't
    # spawn anything, just records bridges that announce themselves via
    # HTTP. Safe to always start; no env gate needed.
    children = [Ezagent.Bridge.V1Prototype.Server]

    Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__)
  end
end
