defmodule EzagentPluginCc.MixProject do
  use Mix.Project

  def project do
    [
      app: :ezagent_plugin_cc,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :yaml_elixir],
      mod: {EzagentPluginCc.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ezagent_core, in_umbrella: true},
      {:ezagent_domain_identity, in_umbrella: true},
      {:ezagent_domain_workspace, in_umbrella: true},
      # Deliberately NOT depending on ezagent_domain_chat: chat depends
      # on us (Chat.invoke(:receive) calls EzagentPluginCc.BridgeRegistry.lookup),
      # so a reverse dep would cycle. The Channel module references
      # Ezagent.Message (core, not chat) for the reply envelope; no
      # other chat-domain calls.
      # Absorbed from the deleted ezagent_plugin_cc_channel:
      # Phoenix.Socket/Channel for the v2 WS bridge mounted at
      # /cc_socket in EzagentWeb.Endpoint.
      {:phoenix, "~> 1.8.0"},
      # YAML parsing for TokenStore's cc-channels.yaml persistence.
      {:yaml_elixir, "~> 2.9"},
      # PTY-side dep: erlexec for the Claude Code TUI lifecycle.
      {:erlexec, "~> 2.1"}
    ]
  end
end
