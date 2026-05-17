defmodule EsrPluginFeishu.InboundDispatcher do
  @moduledoc """
  Phase 6 PR 15 — single entry point shared by `WebhookPlug` and the
  upcoming `WsClient`. Decoupled from transport.

  Responsibilities (in order):

    1. Resolve sender via `SenderResolver`.
    2. If pending → log + react `:eyes` emoji so the human sees ESR
       got the message but ops needs to bind their identity.
    3. If bound → look up session for chat_id, dispatch into it.
       On success, react `:OK` emoji as ergonomic ack (Allen
       2026-05-17 "受到了信息" 反馈).
    4. On any error → no react (the lack of emoji IS the signal).

  ## Why a module not a function in WebhookPlug

  Both inbound transports (HTTP webhook + WS long-connect) flow
  through here so we get identical behavior. Pulling it out makes
  the WS module trivial — it just constructs the keyword args list
  and calls `dispatch/1`.
  """

  require Logger

  alias EsrPluginFeishu.{Client, SenderResolver}

  @type opts :: [
          chat_id: String.t(),
          message_id: String.t() | nil,
          sender: map(),
          body: %{required(:text) => String.t(), required(:attachments) => [map()]}
        ]

  @spec dispatch(opts()) :: :ok | {:error, term()}
  def dispatch(opts) do
    chat_id = Keyword.fetch!(opts, :chat_id)
    message_id = Keyword.get(opts, :message_id)
    sender = Keyword.fetch!(opts, :sender)
    body = Keyword.fetch!(opts, :body)

    case SenderResolver.resolve(sender) do
      {:pending, open_id} ->
        Logger.info(
          "Feishu inbound: open_id=#{open_id} unbound — pending. Run `mix esr.feishu.bind #{open_id} user://<name>` to attach."
        )

        react_safe(message_id, "EYES")
        :ok

      {:ok, caller_uri, caps} ->
        case lookup_session_for_chat(chat_id) do
          {:ok, session_uri} ->
            do_dispatch(session_uri, caller_uri, caps, body)
            react_safe(message_id, "OK")
            :ok

          :error ->
            Logger.info(
              "Feishu inbound: no session binding for chat_id #{chat_id} — drop (no react)"
            )

            {:error, :no_chat_binding}
        end

      {:error, reason} ->
        Logger.warning("Feishu inbound: sender resolve failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Reverse lookup chat_id → session_uri via routing_rules (same shape
  # as the prior WebhookPlug version — Plan B routing rule
  # `in_session(session_uri) → [feishu://<chat_id>]`).
  defp lookup_session_for_chat(chat_id) do
    feishu_uri_str = "feishu://" <> chat_id

    Esr.Routing.RuleStore.list(EsrDomainChat.Routing.MentionRouting)
    |> Enum.find_value(:error, fn row ->
      cond do
        not (feishu_uri_str in row.receivers) ->
          nil

        true ->
          case row.matcher_data do
            %{"type" => "in_session", "arg" => session_uri_str} ->
              {:ok, URI.parse(session_uri_str)}

            _ ->
              nil
          end
      end
    end)
  end

  defp do_dispatch(session_uri, caller_uri, caps, body) do
    # Phase 6 PR 15: download attachments to local paths so recipients
    # (CC bridge, LV chat thread, future viewers) can show content
    # rather than just metadata. Best-effort — download failure keeps
    # the attachment with type+name only.
    body = Map.update(body, :attachments, [], fn list -> Enum.map(list, &maybe_download/1) end)
    msg = Esr.Message.new(caller_uri, body)

    target = URI.parse("#{URI.to_string(session_uri)}/behavior/chat/send")

    inv = %Esr.Invocation{
      target: target,
      mode: :cast,
      args: %{message: msg},
      ctx: %{caller: caller_uri, caps: caps, reply: :ignore}
    }

    case Esr.Invocation.dispatch(inv) do
      {:ok, _} -> :ok
      :ok -> :ok
      {:error, reason} -> Logger.warning("Feishu inbound dispatch failed: #{inspect(reason)}")
    end
  end

  # Best-effort react — failures are non-fatal (network blip on
  # Feishu side shouldn't escalate). `message_id` may be nil for
  # event types without one.
  defp react_safe(nil, _), do: :ok

  defp react_safe(message_id, emoji) do
    case Client.react(message_id, emoji) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.debug("Feishu react #{emoji} on #{message_id} failed: #{inspect(reason)}")
        :ok
    end
  end

  # --- attachment download (moved from WebhookPlug PR 14) ---------------

  defp maybe_download(%{file_key: nil} = att), do: att

  defp maybe_download(%{type: type, file_key: key, message_id: mid, name: name} = att)
       when is_binary(key) and is_binary(mid) do
    feishu_type = feishu_resource_type(type)

    case Client.download_resource(mid, key, feishu_type, name) do
      {:ok, path} ->
        Map.put(att, :local_path, path)

      {:error, reason} ->
        Logger.warning(
          "Feishu inbound: download #{type}/#{name} failed: #{inspect(reason)} — metadata-only forward"
        )

        att
    end
  end

  defp maybe_download(att), do: att

  defp feishu_resource_type(:image), do: "image"
  defp feishu_resource_type(:file), do: "file"
  defp feishu_resource_type(:audio), do: "file"
  defp feishu_resource_type(:video), do: "file"
  defp feishu_resource_type(_), do: "file"
end
