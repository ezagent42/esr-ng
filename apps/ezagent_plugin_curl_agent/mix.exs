defmodule EzagentPluginCurlAgent.MixProject do
  use Mix.Project

  def project do
    [
      app: :ezagent_plugin_curl_agent,
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
      extra_applications: [:logger, :inets, :ssl],
      mod: {EzagentPluginCurlAgent.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ezagent_core, in_umbrella: true},
      # User Kind lives here; CurlAgent dispatches identity/get_api_key
      # against the caller User to fetch the per-user DeepSeek key.
      {:ezagent_domain_identity, in_umbrella: true},
      # Template Class registers against the workspace template catalog.
      {:ezagent_domain_workspace, in_umbrella: true},
      # Outbound chat/send dispatch into the originating session uses
      # the Chat behavior (no new outbound wire).
      {:ezagent_domain_chat, in_umbrella: true}
    ]
  end
end
