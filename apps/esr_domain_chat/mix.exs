defmodule EsrDomainChat.MixProject do
  use Mix.Project

  def project do
    [
      app: :esr_domain_chat,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {EsrDomainChat.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:esr_core, in_umbrella: true},
      # Chat references User Kind (admin join, :receive on User) and
      # Workspace.Loader (boot_complete in start callback). The dep
      # order also enforces start order: identity → workspace → chat.
      {:esr_domain_identity, in_umbrella: true},
      {:esr_domain_workspace, in_umbrella: true},
      # Phase 6 PR 4: Chat.invoke(:receive) for Agent prefers the v2
      # CC channel BridgeRegistry; falls back to v1_prototype while
      # both transports coexist. Both layer-violation-exempt — v1 to
      # be deleted in Phase 7, v2 stays as the official bridge.
      # layer-violation-exempt: cc-bridge-cutover-window
      {:esr_plugin_cc_bridge_v1_prototype, in_umbrella: true},
      # layer-violation-exempt: cc-bridge-cutover-window
      {:esr_plugin_cc_channel, in_umbrella: true}
    ]
  end
end
