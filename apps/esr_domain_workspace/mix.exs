defmodule EsrDomainWorkspace.MixProject do
  use Mix.Project

  def project do
    [
      app: :esr_domain_workspace,
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

  # Phase 6 PR 2: workspace domain — Workspace Kind + Workspace
  # Behavior + the loader/store that lift persisted Workspaces back
  # into running Kinds at boot. Owned by core team.
  def application do
    [
      mod: {EsrDomainWorkspace.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:esr_core, in_umbrella: true},
      # Workspace.Loader uses admin caps from User Kind.
      {:esr_domain_identity, in_umbrella: true}
    ]
  end
end
