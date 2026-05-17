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
      {:esr_domain_identity, in_umbrella: true},
      {:esr_domain_workspace, in_umbrella: true},
      # NOTE: deliberately do NOT depend on :esr_web here. esr_web
      # owns routing and references this plugin's LiveView modules by
      # atom — having the plugin also depend on esr_web would create a
      # compile cycle. The plugin uses Phoenix.LiveView directly.
      {:phoenix_live_view, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:jason, "~> 1.2"},
      # Phase 1 1b: the /admin LV displays the v1 bridge status. This
      # is a v1_prototype coupling — Phase 5 wholesale-replaces the
      # bridge with the production plugin and the LV will subscribe
      # to a class of bridge topics rather than name a specific module.
      {:esr_plugin_cc_bridge_v1_prototype, in_umbrella: true},
      # Phase 2: the /admin LV displays Session membership (online/
      # offline) sourced from `Esr.Behavior.Chat`. Same shape as the
      # cc-bridge coupling — Phase 3+ may abstract the LV's "what
      # session UI to show" via configuration rather than direct dep.
      {:esr_domain_chat, in_umbrella: true},
      # Phase 4 PR 8: cc-pty Template Class — registers via
      # TemplateRegistry; needed at LV mount to render add-template
      # form fields and PTY status pages.
      {:esr_plugin_cc_pty, in_umbrella: true},
      # Phase 5 PR 5: cc-channel registration plugin — Template Class
      # for CC instance registration (token-based bridge auth).
      {:esr_plugin_cc_channel, in_umbrella: true},
      # Phase 5 PR 6: Feishu adapter — Template Class for
      # session ↔ chat_id binding + outbound subscriber + webhook plug.
      # Direct dep ensures Application.start fires + WebhookPlug compiles.
      {:esr_plugin_feishu, in_umbrella: true}
    ]
  end
end
