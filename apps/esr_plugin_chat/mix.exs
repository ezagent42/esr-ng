defmodule EsrPluginChat.MixProject do
  use Mix.Project

  def project do
    [
      app: :esr_plugin_chat,
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

  def application do
    [
      mod: {EsrPluginChat.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:esr_core, in_umbrella: true},
      # Phase 2c: Chat.invoke(:receive) for Agent Kinds pushes the
      # message body to claude via the bridge's SSE topic. Same
      # v1_prototype coupling as the LV admin page — Phase 5 replaces
      # both with the proper esr_plugin_cc_channel.
      {:esr_plugin_cc_bridge_v1_prototype, in_umbrella: true}
    ]
  end
end
