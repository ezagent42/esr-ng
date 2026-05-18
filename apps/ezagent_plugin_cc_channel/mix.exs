defmodule EzagentPluginCcChannel.MixProject do
  use Mix.Project

  def project do
    [
      app: :ezagent_plugin_cc_channel,
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
      mod: {EzagentPluginCcChannel.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ezagent_core, in_umbrella: true},
      {:ezagent_domain_identity, in_umbrella: true},
      {:ezagent_domain_workspace, in_umbrella: true},
      {:yaml_elixir, "~> 2.9"},
      # Phase 6 PR 4: Phoenix Socket + Channel for v2 CC bridge transport.
      {:phoenix, "~> 1.8.0"}
    ]
  end
end
