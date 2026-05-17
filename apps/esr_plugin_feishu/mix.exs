defmodule EsrPluginFeishu.MixProject do
  use Mix.Project

  def project do
    [
      app: :esr_plugin_feishu,
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
      extra_applications: [:logger, :inets, :ssl, :crypto],
      mod: {EsrPluginFeishu.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:esr_core, in_umbrella: true},
      {:esr_domain_identity, in_umbrella: true},
      {:esr_domain_workspace, in_umbrella: true},
      {:esr_domain_chat, in_umbrella: true},
      {:jason, "~> 1.2"},
      {:plug, "~> 1.18"},
      {:yaml_elixir, "~> 2.9"}
    ]
  end
end
