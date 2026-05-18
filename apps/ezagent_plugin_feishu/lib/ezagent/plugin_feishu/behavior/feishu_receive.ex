defmodule EzagentPluginFeishu.Behavior.FeishuReceive do
  @moduledoc """
  Phase 5 Plan B — `:receive` action for `Ezagent.Entity.FeishuChat` Kind.

  Implements the same shape as `Ezagent.Behavior.Chat`'s `:receive` action
  (so the existing dispatch path from `Chat.invoke(:send) → dispatch
  receive to each receiver` works transparently — the Resolver sees
  feishu URIs in the receiver list and ESR core treats them like any
  other receiver Kind).

  ## What it does

  Translates the inbound `%Ezagent.Message{}` into a formatted text and
  calls `EzagentPluginFeishu.Client.send_text(chat_id, text)`. Self-echo
  prevention: if `msg.sender` is a `user://feishu/*` URI, skip — that
  message originated from Feishu and was inbound via WebhookPlug,
  forwarding it back would loop.

  ## Slice

  `:feishu_send` tracks `{send_calls, total_bytes}` for operator
  observability via the existing per-Kind state dump.
  """

  @behaviour Ezagent.Behavior

  require Logger

  alias Ezagent.Message

  @impl Ezagent.Behavior
  def actions, do: [:receive]

  @impl Ezagent.Behavior
  def state_slice, do: :feishu_send

  @impl Ezagent.Behavior
  def init_slice(_args), do: %{send_calls: 0, total_bytes: 0}

  @impl Ezagent.Behavior
  def invoke(:receive, slice, %{message: %Message{} = msg}, ctx) do
    self_uri = Map.get(ctx, :self_uri) || ctx[:target_uri]
    chat_id = Ezagent.Entity.FeishuChat.chat_id_from_uri(self_uri)

    if from_feishu?(msg.sender) do
      Logger.debug(
        "feishu_chat #{chat_id}: skipping self-echo from #{URI.to_string(msg.sender)}"
      )

      {:ok, slice, %{skipped: :self_echo}}
    else
      text = extract_text(msg.body)
      attachments = extract_attachments(msg.body)
      sender_label = sender_label(msg.sender)
      source_session = source_session_label(ctx)
      prefix = "[#{source_session} | #{sender_label}] "

      # Phase 6 PR 14: send each attachment as the matching Feishu
      # message_type. Text-only path stays unchanged. Mixed messages
      # (text + attachments) send the text first then attachments.
      text_result =
        if text != "" do
          formatted = prefix <> text
          EzagentPluginFeishu.Client.send_text(chat_id, formatted)
        else
          :ok
        end

      attachment_results =
        Enum.map(attachments, fn att ->
          send_attachment(chat_id, att, prefix)
        end)

      ok_count = Enum.count(attachment_results, &(&1 == :ok))
      failures = Enum.filter(attachment_results, &match?({:error, _}, &1))

      cond do
        text_result == :ok and failures == [] ->
          {:ok,
           %{
             slice
             | send_calls: slice.send_calls + 1,
               total_bytes:
                 slice.total_bytes + byte_size(text || "") +
                   Enum.sum(Enum.map(attachments, &(&1[:size_bytes] || 0)))
           }, %{bytes_sent: byte_size(text || ""), attachments_sent: ok_count}}

        true ->
          Logger.warning(
            "feishu_chat #{chat_id}: send failures text=#{inspect(text_result)} attachments=#{inspect(failures)}"
          )

          {:error, {:partial_send, text_result, failures}}
      end
    end
  end

  defp send_attachment(chat_id, %{type: type, source: "feishu", file_key: file_key} = att, prefix)
       when is_binary(file_key) do
    # Inbound attachment from Feishu (sent by user). Forward by the
    # original file_key — Feishu accepts it without re-upload as long
    # as the same app owns both ends.
    case type do
      :image ->
        _ = EzagentPluginFeishu.Client.send_text(chat_id, prefix <> "[image: #{att[:name]}]")
        EzagentPluginFeishu.Client.send_image(chat_id, file_key)

      :file ->
        _ = EzagentPluginFeishu.Client.send_text(chat_id, prefix <> "[file: #{att[:name]}]")
        EzagentPluginFeishu.Client.send_file(chat_id, file_key)

      _ ->
        EzagentPluginFeishu.Client.send_text(
          chat_id,
          prefix <> "[unsupported attachment type=#{type} name=#{att[:name]}]"
        )
    end
  end

  defp send_attachment(chat_id, %{type: type, local_path: path, name: name} = att, prefix)
       when is_binary(path) do
    # Outbound attachment from CC / agent — upload bytes from local path.
    case type do
      :image ->
        with {:ok, image_key} <- EzagentPluginFeishu.Client.upload_image(path) do
          _ = EzagentPluginFeishu.Client.send_text(chat_id, prefix <> "[image: #{name}]")
          EzagentPluginFeishu.Client.send_image(chat_id, image_key)
        end

      :file ->
        with {:ok, file_key} <- EzagentPluginFeishu.Client.upload_file(path, name) do
          _ = EzagentPluginFeishu.Client.send_text(chat_id, prefix <> "[file: #{name}]")
          EzagentPluginFeishu.Client.send_file(chat_id, file_key)
        end

      _ ->
        EzagentPluginFeishu.Client.send_text(
          chat_id,
          prefix <> "[unsupported outbound attachment type=#{type} path=#{path}]"
        )
    end
  end

  defp send_attachment(chat_id, att, prefix) do
    EzagentPluginFeishu.Client.send_text(
      chat_id,
      prefix <> "[attachment metadata only: #{inspect(att)}]"
    )
  end

  @impl Ezagent.Behavior
  def interface do
    # Mirror Ezagent.Behavior.Chat's message schema — same dispatch path
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
  defp extract_text(other) when is_map(other), do: ""
  defp extract_text(other), do: inspect(other)

  defp extract_attachments(%{attachments: list}) when is_list(list), do: list
  defp extract_attachments(%{"attachments" => list}) when is_list(list), do: normalize(list)
  defp extract_attachments(_), do: []

  defp normalize(list), do: Enum.map(list, &normalize_one/1)

  defp normalize_one(%{} = m) do
    Map.new(m, fn
      {k, v} when is_binary(k) -> {String.to_atom(k), normalize_value(k, v)}
      kv -> kv
    end)
  end

  defp normalize_one(other), do: other

  defp normalize_value("type", v) when is_binary(v), do: String.to_atom(v)
  defp normalize_value(_, v), do: v

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
