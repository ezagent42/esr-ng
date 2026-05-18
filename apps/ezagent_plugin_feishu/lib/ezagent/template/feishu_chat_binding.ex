defmodule Ezagent.Template.FeishuChatBinding do
  @moduledoc """
  Phase 5 Plan B — Feishu chat ↔ session binding Template Class.

  ARCH-aligned shape (per Allen 2026-05-17 directive). On instantiate:

  1. Spawn the `feishu://oc_xxx` Receiver Kind under
     `EzagentPluginFeishu.FeishuChatSupervisor` via SpawnRegistry
  2. Add a routing rule to MentionRouting:
     `in_session(session_uri) → [feishu://oc_xxx]`
     scoped by `in_session` matcher so it ONLY fires for messages
     originating in this session (not all sessions globally)

  Resolver naturally routes session messages to the Feishu Kind via
  the standard dispatch path; `EzagentPluginFeishu.Behavior.FeishuReceive`
  invocation handles the lark API call. No PubSub side-channel.

  Re-instantiate is idempotent: SpawnRegistry returns `{:ok, existing}`
  for live Kinds; RuleStore allows duplicate rows but we de-dupe by
  checking RuleStore for an equivalent rule first.
  """

  @behaviour Ezagent.Kind.Template
  @behaviour Ezagent.UI.Form

  require Logger

  alias Ezagent.Routing.{Matcher, RuleStore}
  alias EzagentDomainChat.Routing.MentionRouting

  @impl Ezagent.Kind.Template
  def template_name, do: "feishu.chat_binding"

  @impl Ezagent.Kind.Template
  def validate(%{"class" => "feishu.chat_binding", "session_uri" => s, "chat_id" => c})
      when is_binary(s) and is_binary(c) and s != "" and c != "" do
    case URI.new(s) do
      {:ok, %URI{scheme: "session"}} ->
        if String.starts_with?(c, "oc_"), do: :ok, else: {:error, :chat_id_must_start_with_oc_}

      _ ->
        {:error, {:bad_session_uri, s}}
    end
  end

  def validate(%{"class" => "feishu.chat_binding"}),
    do: {:error, :missing_session_uri_or_chat_id}

  def validate(_), do: {:error, :missing_class}

  @impl Ezagent.Kind.Template
  def instantiate(_tmpl_name, %{"session_uri" => session_uri_str, "chat_id" => chat_id}, _ws_uri) do
    session_uri = URI.parse(session_uri_str)
    feishu_uri = Ezagent.Entity.FeishuChat.uri_for(chat_id)

    with {:ok, _pid} <- spawn_feishu_kind(feishu_uri),
         :ok <- ensure_routing_rule(session_uri, feishu_uri) do
      Logger.info(
        "feishu.chat_binding: ARCH-aligned binding live — #{session_uri_str} → #{URI.to_string(feishu_uri)}"
      )

      {:ok, [feishu_uri]}
    end
  end

  defp spawn_feishu_kind(feishu_uri) do
    case Ezagent.KindRegistry.lookup(feishu_uri) do
      {:ok, pid} -> {:ok, pid}
      :error -> Ezagent.SpawnRegistry.spawn(feishu_uri)
    end
  end

  defp ensure_routing_rule(session_uri, feishu_uri) do
    matcher = Matcher.in_session(session_uri)
    receiver_str = URI.to_string(feishu_uri)

    if rule_already_present?(matcher, receiver_str) do
      :ok
    else
      case RuleStore.add(
             MentionRouting,
             matcher,
             [receiver_str],
             nil,
             source: RuleStore.admin_source()
           ) do
        {:ok, _row} ->
          :ok = RuleStore.load_into_registry(MentionRouting)
          :ok

        {:error, reason} ->
          Logger.warning(
            "feishu.chat_binding: failed to add routing rule #{inspect(reason)}; " <>
              "continuing — operator can add via /admin/routing"
          )

          :ok
      end
    end
  end

  defp rule_already_present?(matcher, receiver_str) do
    matcher_json = Matcher.to_json(matcher)

    Enum.any?(RuleStore.list(MentionRouting), fn row ->
      row.matcher_data == matcher_json and receiver_str in row.receivers
    end)
  end

  # --- Ezagent.UI.Form --------------------------------------------------------

  @impl Ezagent.UI.Form
  def form_fields do
    [
      %{
        name: "session_uri",
        type: :uri,
        label: "Session URI",
        required: true,
        placeholder: "session://main"
      },
      %{
        name: "chat_id",
        type: :text,
        label: "Feishu chat_id",
        required: true,
        placeholder: "oc_..."
      }
    ]
  end
end
