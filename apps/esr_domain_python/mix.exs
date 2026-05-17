defmodule EsrDomainPython.MixProject do
  use Mix.Project

  def project do
    [
      app: :esr_domain_python,
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

  # Phase 6 PR 11: Python domain placeholder.
  #
  # First-class hook for ESR's "Python plugin ecosystem" north-star.
  # Today: defines the JSON-RPC stdio CONTRACT a Python plugin would
  # speak — no runtime implementation. Phase 7+ implements the actual
  # subprocess host (port + protocol multiplexer + supervisor).
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
      {:jason, "~> 1.2"}
    ]
  end
end
