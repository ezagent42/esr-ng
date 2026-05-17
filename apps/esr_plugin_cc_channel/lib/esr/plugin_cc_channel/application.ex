defmodule EsrPluginCcChannel.Application do
  @moduledoc """
  Phase 5 PR 5 — CC channel registration plugin.

  v1 scope: provides the **operator-facing registration shell** for CC
  instances. Per Allen's 2026-05-17 directive + SPEC_REVIEW Drift 3,
  registration is a Template Class (`cc.channel_instance`) — NOT a
  bespoke LV form. Operators add a CC instance the same way they add
  a cc.pty agent: WorkspaceDetailLive → add template → pick class.

  ## What's in v1

  - `Esr.Template.CcChannelInstance` — Template Class with form_fields/0
  - `EsrPluginCcChannel.TokenStore` — mints + persists connect tokens
    to `$ESR_HOME/<profile>/credentials/cc-channels.yaml`
  - Token lookup helper for incoming bridge auth

  ## What's NOT in v1 (deferred to PR 5b)

  The Phase 1 `esr_plugin_cc_bridge_v1_prototype` continues to be the
  actual wire transport (HTTP announce + SSE). Production WS rewrite
  + Phoenix.Channel handshake replaces it in a follow-up. This is
  intentional scope-cut: the architectural shape (Template-driven
  registration + token-based identity) lands NOW so future plugins
  can dogfood it; the wire swap is mechanical and can land separately
  without breaking operator workflow.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = []

    case Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__) do
      {:ok, sup_pid} ->
        :ok = register_template_class()
        _ = Esr.Workspace.Loader.load_all()
        {:ok, sup_pid}

      other ->
        other
    end
  end

  defp register_template_class do
    :ok = Esr.TemplateRegistry.register(Esr.Template.CcChannelInstance)
    :ok
  end
end
