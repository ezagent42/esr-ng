defmodule EsrDomainUi.MixProject do
  use Mix.Project

  def project do
    [
      app: :esr_domain_ui,
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

  # Phase 6 PR 3: ui domain — shadcn-like HEEx component primitives
  # any plugin (including ezagent_plugin_liveview) can use to build pages.
  # No GenServer; library only.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix_live_view, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"}
    ]
  end
end
