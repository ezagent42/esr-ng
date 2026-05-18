defmodule EzagentPluginCcChannel.Application do
  @moduledoc """
  Phase 5 PR 5 — CC channel registration plugin.

  v1 scope: provides the **operator-facing registration shell** for CC
  instances. Per Allen's 2026-05-17 directive + SPEC_REVIEW Drift 3,
  registration is a Template Class (`cc.channel_instance`) — NOT a
  bespoke LV form. Operators add a CC instance the same way they add
  a cc.pty agent: WorkspaceDetailLive → add template → pick class.

  ## What's in v1

  - `Ezagent.Template.CcChannelInstance` — Template Class with form_fields/0
  - `EzagentPluginCcChannel.TokenStore` — mints + persists connect tokens
    to `$EZAGENT_HOME/<profile>/credentials/cc-channels.yaml`
  - Token lookup helper for incoming bridge auth

  ## Phase 6 PR 4 (this commit)

  Adds the production WS wire transport: `EzagentPluginCcChannel.Socket`
  + `EzagentPluginCcChannel.Channel` mounted at `/cc_socket` in
  `EzagentWeb.Endpoint`. Token auth via existing TokenStore.
  `EzagentPluginCcChannel.BridgeRegistry` is the in-memory
  `agent_uri → channel_pid` table used by the chat plugin's Agent
  receive path.

  v1_prototype (`ezagent_plugin_cc_bridge_v1_prototype`) is deprecated
  but still wired so existing Python bridges continue to work during
  the cutover window. Phase 7 deletes v1 after the Python bridge
  migrates to the WS client.
  """

  use Application

  alias EzagentPluginCcChannel.BridgeRegistry

  @impl true
  def start(_type, _args) do
    :ok = BridgeRegistry.init()

    children = []

    case Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__) do
      {:ok, sup_pid} ->
        :ok = register_template_class()
        _ = Ezagent.Workspace.Loader.load_all()
        {:ok, sup_pid}

      other ->
        other
    end
  end

  defp register_template_class do
    :ok = Ezagent.TemplateRegistry.register(Ezagent.Template.CcChannelInstance)
    :ok
  end
end
