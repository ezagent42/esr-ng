defmodule EzagentPluginFeishu.Application do
  @moduledoc """
  Feishu adapter plugin — SPEC v2 §5.8 shape (PR #144).

  ## §5.8 — no plugin-owned schemes

  The PR #144 re-shape deleted the `feishu://oc_xxx` Receiver Kind.
  In its place:

  - **Inbound** (Feishu → Ezagent): `InboundDispatcher` resolves
    `sender_open_id → entity://user/<X>` via `FeishuUserBinding` and
    `chat_id → session://<template>/<name>` via the new
    `FeishuSessionBinding` join table, then dispatches
    `<session_uri>?action=chat.send` with the message.
  - **Outbound** (Ezagent → Feishu): `Behavior.FeishuOutbound`
    registers against `Ezagent.Entity.Session` for action
    `:notify_external`. `Behavior.Chat.invoke(:send)` opportunistically
    dispatches `notify_external` after fan-out; the behavior reads
    the session's binding(s) and mirrors via the Feishu Open API.

  Per `feedback_plugin_external_integration_is_receiver_kind`: any
  future plugin that sends messages out of Ezagent (Slack, Discord,
  email, webhook, …) MUST follow this Behavior-on-existing-Kind
  pattern, NOT introduce a new top-level scheme.

  ## Boot

  1. Start FeishuChatSupervisor (DynamicSupervisor — retained as
     a stable name even though no `feishu://` Kinds are spawned
     under it post-PR-144; future intra-plugin processes can supervise
     here)
  2. Start Client GenServer (Lark token cache + send endpoints)
  3. Register `EzagentPluginFeishu.Behavior.FeishuOutbound` on
     `Ezagent.Entity.Session` for `:notify_external` action
  4. Re-run `Ezagent.Workspace.Loader.load_all/0` (Decision #112
     boot-ordering)
  5. Seed any bindings from
     `$EZAGENT_HOME/<profile>/plugins/feishu/initial_bindings.yaml`
     (each binding becomes a `FeishuSessionBinding` row directly —
     no Kind spawn, no routing-rule write)
  """

  use Application
  require Logger

  alias Ezagent.BehaviorRegistry
  alias Ezagent.Entity.Session, as: SessionKind
  alias EzagentPluginFeishu.Behavior.FeishuOutbound

  @impl true
  def start(_type, _args) do
    children = [
      {DynamicSupervisor, name: EzagentPluginFeishu.FeishuChatSupervisor, strategy: :one_for_one},
      EzagentPluginFeishu.Client,
      # Phase 6 PR 15: WS long-connect to Feishu. Skipped at test boot
      # (Mix.env() == :test) and when EZAGENT_FEISHU_WS=0 (operator opt-out).
      maybe_ws_client_spec()
    ]
    |> Enum.reject(&is_nil/1)

    case Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__) do
      {:ok, sup_pid} ->
        :ok = register_behaviors()
        _ = Ezagent.Workspace.Loader.load_all()
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
      EzagentPluginFeishu.WsClient
    end
  end

  # PR #144 SPEC v2 §5.8 — FeishuOutbound registers against the
  # existing `Ezagent.Entity.Session` Kind for the generic
  # `:notify_external` action. `Ezagent.Behavior.Chat.invoke(:send)`
  # dispatches that action after fan-out (opportunistic — no-op if
  # nothing is registered).
  defp register_behaviors do
    Enum.each(FeishuOutbound.actions(), fn action ->
      :ok = BehaviorRegistry.register(SessionKind, action, FeishuOutbound)
    end)

    :ok
  end

  defp seed_initial_bindings do
    # Hotfix carried over from PR #133: skip in test env so the test
    # suite doesn't leak real network calls to Feishu (boot-seeded
    # subscribers forwarded test messages to real chats — Allen
    # observed this 2026-05-17).
    if Mix.env() == :test do
      :ok
    else
      do_seed_initial_bindings()
    end
  end

  defp do_seed_initial_bindings do
    file = Path.join([Ezagent.Home.path(:plugins), "feishu", "initial_bindings.yaml"])

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
      target_session = Map.get(binding, "session_uri") || "session://main"

      if is_binary(chat_id) and chat_id != "" do
        Logger.info(
          "Feishu plugin: seeding initial binding chat_id=#{chat_id} → #{target_session}"
        )

        case EzagentPluginFeishu.SessionBinding.bind(chat_id, target_session) do
          {:ok, _row} ->
            :ok

          {:error, reason} ->
            Logger.warning(
              "Feishu plugin: initial binding chat_id=#{chat_id} failed: #{inspect(reason)}"
            )
        end
      end
    end)

    :ok
  end
end
