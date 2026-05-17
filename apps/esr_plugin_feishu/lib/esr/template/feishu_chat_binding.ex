defmodule Esr.Template.FeishuChatBinding do
  @moduledoc """
  Phase 5 PR 6 — Feishu chat ↔ session binding Template Class.

  Per SPEC_REVIEW Drift 1: bindings are Template Class instances, not
  Workspace.config fields. Operator adds a binding via WorkspaceDetailLive
  add-template form (dogfoods PR 2 form_fields).

  ## Template data

      %{
        "class" => "feishu.chat_binding",
        "session_uri" => "session://main",
        "chat_id" => "oc_abc123..."
      }

  ## instantiate/3

  Subscribes an OutboundSubscriber GenServer to the session's PubSub
  topic — every `{:chat_message, session_uri, msg}` event triggers
  `EsrPluginFeishu.Client.send_text(chat_id, msg.body.text)`.

  Inbound (Feishu → ESR) is handled by `EsrPluginFeishu.WebhookPlug` —
  registered in `esr_web/router.ex` (the only LV/web touch this plugin
  makes, since Feishu's webhook needs a publicly-routable HTTP endpoint).

  ## Idempotency

  Re-instantiating with the same `(session_uri, chat_id)` returns
  `{:ok, [binding_uri]}` and the existing subscriber stays alive.
  """

  @behaviour Esr.Kind.Template
  @behaviour Esr.UI.Form

  require Logger

  @impl Esr.Kind.Template
  def template_name, do: "feishu.chat_binding"

  @impl Esr.Kind.Template
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

  @impl Esr.Kind.Template
  def instantiate(_tmpl_name, %{"session_uri" => session_uri_str, "chat_id" => chat_id}, _ws_uri) do
    session_uri = URI.parse(session_uri_str)
    binding_uri = URI.parse("feishu-binding://#{chat_id}")

    case EsrPluginFeishu.OutboundSubscriber.start(session_uri, chat_id) do
      {:ok, _pid} ->
        Logger.info("feishu.chat_binding: #{session_uri_str} ↔ #{chat_id}")
        {:ok, [binding_uri]}

      {:error, {:already_started, _pid}} ->
        {:ok, [binding_uri]}

      err ->
        err
    end
  end

  # --- Esr.UI.Form --------------------------------------------------------

  @impl Esr.UI.Form
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
