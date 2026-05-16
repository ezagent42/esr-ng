defmodule Esr.Entity.Agent do
  @moduledoc """
  Agent Kind — represents an external participant (e.g. a Claude CLI
  session via the CC bridge) inside ESR's chat router.

  Per Decision #61: an Agent is a peer of admin User in the Session —
  it can send messages (when its bridge surfaces a reply) and receive
  messages (forwarded by Session). The Agent Kind itself owns the
  bridge mapping and routes the cross-process traffic — see
  `Esr.Bridge.V1Prototype.Server` for the wire side.

  ## Spawn lifecycle

  Phase 2 does NOT spawn any Agent at boot. Agent Kinds materialize
  when a bridge announces itself:

      Bridge announce (HTTP POST /announce)
        → Esr.CcBridgeAnnounceController.announce/2
        → DynamicSupervisor.start_child(EsrPluginChat.AgentSupervisor,
            {Esr.Kind.Server, {Esr.Entity.Agent, %{uri: agent_uri}}})

  This is the realization of memory `feedback_north_star_plugin_isolation`:
  the Agent module knows nothing about bridges; the controller knows
  nothing about Chat. The DynamicSupervisor + Esr.Kind.Server are the
  only contact points, and they're both `esr_core` machinery.

  ## URI shape

  Bridges supply `agent_uri` via `ESR_AGENT_URI` env (per
  cc-bridge-attach.sh contract — zero hardcoded URI in code). Phase 2
  demo URI is `agent://cc-builder` but anything matching `agent://*`
  works at the routing layer.
  """

  @behaviour Esr.Kind

  @impl Esr.Kind
  def type_name, do: :agent

  # Phase 3d: Agent carries Identity Behavior alongside Chat. Default
  # initial_caps is empty (Agent has no authority to initiate; chat
  # receive only). Operators can grant caps via Identity invoke if
  # they want to elevate a specific Agent.
  @impl Esr.Kind
  def behaviors, do: [Esr.Behavior.Chat, Esr.Behavior.Identity]

  @impl Esr.Kind
  def persistence, do: :ephemeral
end
