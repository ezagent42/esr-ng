defmodule EsrPluginFeishu.Behavior.FeishuReceive do
  @moduledoc """
  Phase 5 Plan B — `:receive` action for `Esr.Entity.FeishuChat` Kind.

  Implements the same shape as `Esr.Behavior.Chat`'s `:receive` action
  (so the existing dispatch path from `Chat.invoke(:send) → dispatch
  receive to each receiver` works transparently — the Resolver sees
  feishu URIs in the receiver list and ESR core treats them like any
  other receiver Kind).

  ## What it does

  Translates the inbound `%Esr.Message{}` into a formatted text and
  calls `EsrPluginFeishu.Client.send_text(chat_id, text)`. Self-echo
  prevention: if `msg.sender` is a `user://feishu/*` URI, skip — that
  message originated from Feishu and was inbound via WebhookPlug,
  forwarding it back would loop.

  ## Slice

  `:feishu_send` tracks `{send_calls, total_bytes}` for operator
  observability via the existing per-Kind state dump.
  """

  @behaviour Esr.Behavior

  require Logger

  alias Esr.Message

  @impl Esr.Behavior
  def actions, do: [:receive]

  @impl Esr.Behavior
  def state_slice, do: :feishu_send

  @impl Esr.Behavior
  def init_slice(_args), do: %{send_calls: 0, total_bytes: 0}

  @impl Esr.Behavior
  def invoke(:receive, slice, %{message: %Message{} = msg}, ctx) do
    self_uri = Map.get(ctx, :self_uri) || ctx[:target_uri]
    chat_id = Esr.Entity.FeishuChat.chat_id_from_uri(self_uri)

    if from_feishu?(msg.sender) do
      Logger.debug(
        "feishu_chat #{chat_id}: skipping self-echo from #{URI.to_string(msg.sender)}"
      )

      {:ok, slice, %{skipped: :self_echo}}
    else
      text = extract_text(msg.body)
      sender_label = sender_label(msg.sender)
      source_session = source_session_label(ctx)
      formatted = "[#{source_session} | #{sender_label}] #{text}"

      case EsrPluginFeishu.Client.send_text(chat_id, formatted) do
        :ok ->
          {:ok,
           %{
             slice
             | send_calls: slice.send_calls + 1,
               total_bytes: slice.total_bytes + byte_size(formatted)
           }, %{bytes_sent: byte_size(formatted)}}

        {:error, reason} = err ->
          Logger.warning("feishu_chat #{chat_id}: send_text failed: #{inspect(reason)}")
          err
      end
    end
  end

  @impl Esr.Behavior
  def interface do
    # Mirror Esr.Behavior.Chat's message schema — same dispatch path
    # delivers the same payload shape. InterfaceValidator rejects bare
    # `:any` for the struct, so the per-field schema is required.
    msg_schema = %{
      uri: :string,
      sender: :uri,
      mentions: {:list, :uri},
      body: :map,
      ref: {:option, :uri},
      inserted_at: :map
    }

    %{
      receive: %{
        args: %{message: msg_schema},
        returns: %{bytes_sent: :integer},
        modes: [:call, :cast]
      }
    }
  end

  defp from_feishu?(%URI{scheme: "user", path: "/feishu/" <> _}), do: true

  defp from_feishu?(%URI{scheme: "user", authority: auth}) when is_binary(auth),
    do: String.starts_with?(auth, "feishu/")

  defp from_feishu?(_), do: false

  defp extract_text(%{text: t}) when is_binary(t), do: t
  defp extract_text(%{"text" => t}) when is_binary(t), do: t
  defp extract_text(other), do: inspect(other)

  defp sender_label(%URI{} = u), do: URI.to_string(u)
  defp sender_label(other), do: inspect(other)

  defp source_session_label(ctx) do
    case Map.get(ctx, :caller) do
      %URI{} = u -> URI.to_string(u)
      s when is_binary(s) -> s
      _ -> "(unknown session)"
    end
  end
end
