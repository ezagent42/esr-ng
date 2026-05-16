defmodule EsrPluginCcPty.MixProject do
  use Mix.Project

  def project do
    [
      app: :esr_plugin_cc_pty,
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
      mod: {EsrPluginCcPty.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:esr_core, in_umbrella: true},
      {:esr_plugin_chat, in_umbrella: true},
      {:erlexec, "~> 2.1"}
    ]
  end
end
