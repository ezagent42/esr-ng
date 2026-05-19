defmodule EzagentPluginCurlAgent.Application do
  @moduledoc """
  CurlAgent plugin OTP application.

  ## Boot sequence

  1. Start `InstanceSupervisor` (DynamicSupervisor for per-instance
     Kind.Server children spawned by the Template Class)
  2. Register `(Entity.CurlAgent, :receive)`, `(Entity.CurlAgent, :reset_conversation)`,
     `(Entity.CurlAgent, :configure)` → `Behavior.CurlAgent` in BehaviorRegistry
  3. Register `curl-agent://` scheme spawn fn for **back-compat only** —
     PR #129 (Allen 2026-05-19) made `agent://` the preferred scheme
     for new curl-agent instances so they appear in the standard
     floating-agents + @-mention dropdowns (those filter on
     `agent://`). Existing `curl-agent://...` rows keep working via
     this spawn fn; the chat plugin's `agent://` spawn fn handles
     normal cc-bridge agents, and `agent://my-deepseek`-style
     curl-agent URIs are spawned directly by the Template Class
     into KindRegistry at workspace load time (so SpawnRegistry's
     KindRegistry-first lookup returns the existing CurlAgent pid
     before chat's fn would create an Entity.Agent — no collision).
  4. Register `curl.agent` Template Class so workspaces can declare
     instances via the standard add-template UI
  """

  use Application

  alias Ezagent.{BehaviorRegistry, TemplateRegistry}
  alias Ezagent.Behavior.CurlAgent, as: CurlAgentBehavior
  alias Ezagent.Entity.CurlAgent, as: CurlAgentKind
  alias Ezagent.PluginCurlAgent.Template, as: CurlAgentTemplate

  @impl true
  def start(_type, _args) do
    children = [
      {DynamicSupervisor, name: EzagentPluginCurlAgent.InstanceSupervisor, strategy: :one_for_one}
    ]

    case Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__) do
      {:ok, sup_pid} ->
        :ok = register_behaviors()
        :ok = register_spawn_fn()
        :ok = register_template_class()
        # Decision #112 boot-ordering: when chat plugin ran
        # Workspace.Loader.load_all/0 before this plugin registered
        # its Template Class, curl.agent templates were skipped.
        # Re-run here so those workspaces get instantiated.
        _ = Ezagent.Workspace.Loader.load_all()
        {:ok, sup_pid}

      other ->
        other
    end
  end

  defp register_behaviors do
    for action <- CurlAgentBehavior.actions() do
      :ok = BehaviorRegistry.register(CurlAgentKind, action, CurlAgentBehavior)
    end

    :ok
  end

  defp register_spawn_fn do
    # PR #131 (Allen 2026-05-19): agent URIs now embed the type via
    # `agent://<type>/<name>`. Register "curl" type → Entity.CurlAgent
    # in the AgentTypeRegistry; chat plugin's `agent://` SpawnRegistry
    # fn delegates here. The legacy `curl-agent://` scheme is no longer
    # registered — old data must be migrated to `agent://curl/<name>`.
    :ok =
      Ezagent.AgentTypeRegistry.register("curl", fn uri, _name ->
        DynamicSupervisor.start_child(
          EzagentPluginCurlAgent.InstanceSupervisor,
          {Ezagent.Kind.Server, {CurlAgentKind, %{uri: uri}}}
        )
      end)

    :ok
  end

  defp register_template_class do
    :ok = TemplateRegistry.register(CurlAgentTemplate)
    :ok
  end
end
