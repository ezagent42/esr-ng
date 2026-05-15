defmodule EsrWebLiveview.MixProject do
  use Mix.Project

  def project do
    [
      app: :esr_web_liveview,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:esr_core, in_umbrella: true},
      # NOTE: deliberately do NOT depend on :esr_web here. esr_web
      # owns routing and references this plugin's LiveView modules by
      # atom — having the plugin also depend on esr_web would create a
      # compile cycle. The plugin uses Phoenix.LiveView directly.
      {:phoenix_live_view, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:jason, "~> 1.2"}
    ]
  end
end
