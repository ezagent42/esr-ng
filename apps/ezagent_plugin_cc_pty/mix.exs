defmodule EzagentPluginCcPty.MixProject do
  use Mix.Project

  def project do
    [
      app: :ezagent_plugin_cc_pty,
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
      extra_applications: [:logger],
      mod: {EzagentPluginCcPty.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ezagent_core, in_umbrella: true},
      {:ezagent_domain_identity, in_umbrella: true},
      {:ezagent_domain_workspace, in_umbrella: true},
      {:ezagent_domain_chat, in_umbrella: true},
      # PtyServer calls v2 McpConfigWriter in-process to generate
      # mcp.json (Phase 7 PR 32b cutover). v1 plugin dep removed in
      # this PR; PR 32c deletes the v1 app entirely.
      {:ezagent_plugin_cc_channel, in_umbrella: true},
      {:erlexec, "~> 2.1"}
    ]
  end
end
