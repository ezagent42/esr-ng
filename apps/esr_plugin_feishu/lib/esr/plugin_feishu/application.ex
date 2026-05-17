defmodule EsrPluginFeishu.Application do
  @moduledoc """
  Phase 5 PR 6 + Plan B (Allen 2026-05-17) — Feishu adapter plugin.

  ## Plan B refactor: Feishu is a Receiver Kind

  Outbound is no longer a side-channel PubSub subscriber. `feishu://oc_xxx`
  is a real Kind (`Esr.Entity.FeishuChat`); its `:receive` action is
  implemented by `EsrPluginFeishu.Behavior.FeishuReceive`, which calls
  the lark API. Resolver fans messages out to it like any other
  Receiver Kind via `Esr.Invocation.dispatch` → CapBAC + audit fire
  on the same path. This is the ARCH-aligned shape per §5.4.4.

  ## Boot

  1. Start FeishuChatSupervisor (DynamicSupervisor for spawned
     `feishu://oc_xxx` Kind.Server children)
  2. Start Client GenServer (Lark token cache + send_text endpoint)
  3. Register Esr.Template.FeishuChatBinding Class
  4. Register feishu:// scheme → SpawnRegistry
  5. Register (FeishuChat, :receive) → FeishuReceive in BehaviorRegistry
  6. Re-run Esr.Workspace.Loader.load_all/0 (Decision #112 boot-ordering)
  7. Seed any bindings from
     `$ESR_HOME/<profile>/plugins/feishu/initial_bindings.yaml`
  """

  use Application
  require Logger

  alias Esr.BehaviorRegistry
  alias Esr.Entity.FeishuChat, as: FK
  alias EsrPluginFeishu.Behavior.FeishuReceive

  @impl true
  def start(_type, _args) do
    children = [
      {DynamicSupervisor, name: EsrPluginFeishu.FeishuChatSupervisor, strategy: :one_for_one},
      EsrPluginFeishu.Client,
      # Phase 6 PR 15: WS long-connect to Feishu. Skipped at test boot
      # (Mix.env() == :test) and when ESR_FEISHU_WS=0 (operator opt-out).
      maybe_ws_client_spec()
    ]
    |> Enum.reject(&is_nil/1)

    case Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__) do
      {:ok, sup_pid} ->
        :ok = register_template_class()
        :ok = register_spawn_fn()
        :ok = register_behaviors()
        _ = Esr.Workspace.Loader.load_all()
        :ok = seed_initial_bindings()
        {:ok, sup_pid}

      other ->
        other
    end
  end

  defp maybe_ws_client_spec do
    if Mix.env() == :test do
      nil
    else
      EsrPluginFeishu.WsClient
    end
  end

  defp register_template_class do
    :ok = Esr.TemplateRegistry.register(Esr.Template.FeishuChatBinding)
    :ok
  end

  defp register_spawn_fn do
    :ok =
      Esr.SpawnRegistry.register("feishu", fn uri ->
        DynamicSupervisor.start_child(
          EsrPluginFeishu.FeishuChatSupervisor,
          {Esr.Kind.Server, {FK, %{uri: uri}}}
        )
      end)

    :ok
  end

  defp register_behaviors do
    Enum.each(FeishuReceive.actions(), fn action ->
      :ok = BehaviorRegistry.register(FK, action, FeishuReceive)
    end)

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
