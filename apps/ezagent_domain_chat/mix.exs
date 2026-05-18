defmodule EzagentDomainChat.MixProject do
  use Mix.Project

  def project do
    [
      app: :ezagent_domain_chat,
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
      mod: {EzagentDomainChat.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ezagent_core, in_umbrella: true},
      # Chat references User Kind (admin join, :receive on User) and
      # Workspace.Loader (boot_complete in start callback). The dep
      # order also enforces start order: identity → workspace → chat.
      {:ezagent_domain_identity, in_umbrella: true},
      {:ezagent_domain_workspace, in_umbrella: true},
      # Chat.invoke(:receive) for Agent dispatches to the v2 CC channel
      # BridgeRegistry. v1 prototype dep + fallback branch removed in
      # PR 32c (rebrand-4) after PtyServer cutover landed in PR 32b.
      # layer-violation-exempt: cc-bridge production wire
      {:ezagent_plugin_cc_channel, in_umbrella: true}
    ]
  end
end
