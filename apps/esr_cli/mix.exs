defmodule EsrCLI.MixProject do
  use Mix.Project

  def project do
    [
      app: :esr_cli,
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
      # :inets + :ssl for :httpc HTTP client used by remote-dispatch
      # (Allen 2026-05-17: CLI POSTs to running server instead of
      # local Esr.Invocation.dispatch).
      extra_applications: [:logger, :inets, :ssl, :crypto],
      mod: {EsrCLI.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:esr_core, in_umbrella: true},
      {:optimus, "~> 0.5"},
      {:jason, ">= 0.0.0"}
    ]
  end
end
