defmodule EsrPluginFeishu.OutboundSubscriber do
  @moduledoc """
  Phase 5 PR 6 — subscribes to a session's chat_message PubSub events
  and forwards user-originated messages to the bound Feishu chat.

  Started by `Esr.Template.FeishuChatBinding.instantiate/3`. One per
  (session_uri, chat_id) binding. Registered in `Esr.KindRegistry`
  under `feishu-binding://<chat_id>` so re-instantiate is idempotent.

  ## Outbound filter

  Only forwards messages **NOT from Feishu users** (sender scheme !=
  `user://feishu/*`) — otherwise we'd echo every inbound back to its
  source. Self-echo prevention. PR 6 follow-up may extend with custom
  routing rules per binding.
  """
  use GenServer
  require Logger

  defstruct [:session_uri, :chat_id]

  def start(%URI{} = session_uri, chat_id) when is_binary(chat_id) do
    key = key_for(chat_id)

    case Esr.KindRegistry.lookup(key) do
      {:ok, pid} ->
        {:ok, pid}

      :error ->
        DynamicSupervisor.start_child(
          EsrPluginFeishu.SubscriberSupervisor,
          {__MODULE__, {session_uri, chat_id}}
        )
    end
  end

  def start_link({session_uri, chat_id}) do
    GenServer.start_link(__MODULE__, {session_uri, chat_id})
  end

  defp key_for(chat_id), do: URI.parse("feishu-binding://#{chat_id}")

  @impl true
  def init({session_uri, chat_id}) do
    key = key_for(chat_id)
    # `put_new` so re-registering the same chat_id idempotent-fails
    # gracefully (already_registered handled by Template caller).
    _ = Esr.KindRegistry.put_new(key)

    Phoenix.PubSub.subscribe(
      EsrCore.PubSub,
      Esr.Behavior.Chat.session_events_topic(session_uri)
    )

    Logger.info("Feishu OutboundSubscriber: #{URI.to_string(session_uri)} → #{chat_id}")
    {:ok, %__MODULE__{session_uri: session_uri, chat_id: chat_id}}
  end

  @impl true
  def handle_info({:chat_message, _src_session_uri, %Esr.Message{} = msg}, state) do
    if from_feishu?(msg.sender) do
      # Skip: this message came from Feishu inbound. Forwarding it
      # back would echo to the same user.
      {:noreply, state}
    else
      text = extract_text(msg.body)
      sender_label = sender_label(msg.sender)
      formatted = "[#{sender_label}] #{text}"

      case EsrPluginFeishu.Client.send_text(state.chat_id, formatted) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning(
            "Feishu outbound failed for #{state.chat_id}: #{inspect(reason)}"
          )
      end

      {:noreply, state}
    end
  end

  def handle_info(_other, state), do: {:noreply, state}

  defp from_feishu?(%URI{scheme: "user", path: path}) when is_binary(path) do
    String.starts_with?(path, "//feishu/") or String.starts_with?(to_string(path), "/feishu/")
  end

  defp from_feishu?(%URI{host: "feishu"}), do: true
  defp from_feishu?(_), do: false

  defp extract_text(%{text: t}) when is_binary(t), do: t
  defp extract_text(%{"text" => t}) when is_binary(t), do: t
  defp extract_text(other), do: inspect(other)

  defp sender_label(%URI{} = u), do: URI.to_string(u)
  defp sender_label(other), do: inspect(other)
end
