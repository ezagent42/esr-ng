defmodule EzagentPluginCurlAgent.Application do
  @moduledoc """
  CurlAgent plugin OTP application.

  ## Boot sequence

  1. Start `InstanceSupervisor` (DynamicSupervisor for per-instance
     Kind.Server children spawned by the Template Class)
  2. Register `(Entity.CurlAgent, :receive)`, `(Entity.CurlAgent, :reset_conversation)`,
     `(Entity.CurlAgent, :configure)` → `Behavior.CurlAgent` in BehaviorRegistry
  3. Register "curl" flavor in `Ezagent.AgentTypeRegistry`. PR #141
     SPEC v2 §5.14: agent URIs are `entity://agent/<flavor>_<name>`;
     chat plugin's `entity://` spawn fn delegates to AgentTypeRegistry
     for `host = "agent"`, which dispatches by flavor to this fn.
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
    # PR #141 (SPEC v2): agent URIs are `entity://agent/<flavor>_<name>`
    # — flavor moves to the name prefix (§5.14). Register "curl" flavor
    # → Entity.CurlAgent in the AgentTypeRegistry; chat plugin's
    # `entity://` SpawnRegistry fn delegates here for `host = "agent"`.
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
