defmodule EsrPluginFeishu.Application do
  @moduledoc """
  Phase 5 PR 6 — Feishu adapter plugin.

  ## Plugin north-star validator

  Per SPEC v2: if this plugin lands with zero changes to esr_core +
  esr_web_liveview (beyond the explicit webhook route in esr_web's
  router.ex), Phase 5 actually delivered the plugin isolation
  north-star (memory `feedback_north_star_plugin_isolation`).

  ## Boot

  1. Start SubscriberSupervisor (DynamicSupervisor for outbound bindings)
  2. Start Client GenServer (Lark token cache + send_text endpoint)
  3. Register Esr.Template.FeishuChatBinding Class
  4. Re-run Esr.Workspace.Loader.load_all/0 (Decision #112 boot-ordering)
  5. Seed any bindings from
     `$ESR_HOME/<profile>/plugins/feishu/initial_bindings.yaml` (written
     by `mix esr.home.import_from_esrd_dev`)
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    children = [
      {DynamicSupervisor, name: EsrPluginFeishu.SubscriberSupervisor, strategy: :one_for_one},
      EsrPluginFeishu.Client
    ]

    case Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__) do
      {:ok, sup_pid} ->
        :ok = register_template_class()
        _ = Esr.Workspace.Loader.load_all()
        :ok = seed_initial_bindings()
        {:ok, sup_pid}

      other ->
        other
    end
  end

  defp register_template_class do
    :ok = Esr.TemplateRegistry.register(Esr.Template.FeishuChatBinding)
    :ok
  end

  defp seed_initial_bindings do
    # Hotfix: skip in test env so the test suite doesn't leak real
    # network calls to Feishu (boot-seeded subscribers forwarded test
    # messages to real chats — Allen observed this 2026-05-17).
    if Mix.env() == :test do
      :ok
    else
      do_seed_initial_bindings()
    end
  end

  defp do_seed_initial_bindings do
    file = Path.join([Esr.Home.path(:plugins), "feishu", "initial_bindings.yaml"])

    case File.read(file) do
      {:ok, body} ->
        case YamlElixir.read_from_string(body) do
          {:ok, %{"bindings" => bindings}} when is_list(bindings) ->
            seed_each(bindings)

          _ ->
            :ok
        end

      _ ->
        :ok
    end
  end

  defp seed_each(bindings) do
    Enum.each(bindings, fn binding ->
      chat_id = Map.get(binding, "chat_id")
      old_session_id = Map.get(binding, "old_session_id")

      # The old esrd sessions have UUID ids; for esr-ng we map them to
      # session://main as a sensible default. Operator can re-bind via
      # the LV form to point at any session.
      target_session = "session://main"

      if is_binary(chat_id) and chat_id != "" do
        Logger.info(
          "Feishu plugin: seeding initial binding chat_id=#{chat_id} (old=#{old_session_id}) → #{target_session}"
        )

        Esr.Template.FeishuChatBinding.instantiate(
          "seed-#{:erlang.phash2({chat_id, target_session})}",
          %{
            "class" => "feishu.chat_binding",
            "session_uri" => target_session,
            "chat_id" => chat_id
          },
          URI.parse("workspace://feishu-seed")
        )
      end
    end)

    :ok
  end
end
