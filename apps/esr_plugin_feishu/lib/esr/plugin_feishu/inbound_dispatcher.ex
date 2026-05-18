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

        # Allen 2026-05-17: lark react API rejected EYES with code
        # 231001 "reaction type is invalid" — lark only accepts a
        # curated emoji set. THUMBSDOWN is on the supported list and
        # is visually distinct from the OK success react below.
        react_safe(message_id, "THUMBSDOWN")
        :ok

      {:ok, caller_uri, caps} ->
        case lookup_session_for_chat(chat_id) do
          {:ok, session_uri} ->
            case do_dispatch(session_uri, caller_uri, caps, body) do
              :ok ->
                react_safe(message_id, "OK")
                :ok

              {:error, :unauthorized} ->
                # PR 27 (Allen 2026-05-18 "silent down 不可接受"): cap
                # denial reaches the human via a text in the original
                # chat + THUMBSDOWN react, not a void log line. The
                # bound user IS the delegate; if they're missing the
                # cap, the right answer is to tell them, not silently
                # drop. Reverse-leg matchers + crash bubbling are
                # tracked in docs/futures/todo.md.
                Logger.info(
                  "Feishu inbound: cap denied for #{URI.to_string(caller_uri)} → " <>
                    "#{URI.to_string(session_uri)}/chat/send; sending text back"
                )

                send_dispatch_error(
                  chat_id,
                  message_id,
                  "❌ ESR: 没有权限发送到 #{URI.to_string(session_uri)} " <>
                    "(missing cap: session.chat). " <>
                    "请联系管理员补一条 `kind=:session behavior=:chat` 的 cap。"
                )

                {:error, :unauthorized}

              {:error, reason} ->
                Logger.warning(
                  "Feishu inbound dispatch failed: #{inspect(reason)} → sending text back"
                )

                send_dispatch_error(
                  chat_id,
                  message_id,
                  "❌ ESR: dispatch 失败: #{inspect(reason)}"
                )

                {:error, reason}
            end

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

    # Phase 6 PR 16: extract @mentions from text (B2 route per Allen
    # 2026-05-17). Resolved live agent URIs go into Message.mentions
    # so the existing MentionRouting matcher routes the message ONLY
    # to the mentioned agent rather than fanning out to all members.
    mentions = EsrPluginFeishu.MentionParser.extract_agent_mentions(body[:text] || "")

    msg = Esr.Message.new(caller_uri, body, mentions: mentions)

    target = URI.parse("#{URI.to_string(session_uri)}/behavior/chat/send")

    # PR 27 (Allen 2026-05-18): mode :call so cap-denial bubbles back
    # synchronously; the caller (dispatch/1) sends a text message to
    # the human explaining the failure. :cast would silently drop —
    # no audit feedback to the sender.
    inv = %Esr.Invocation{
      target: target,
      mode: :call,
      args: %{message: msg},
      ctx: %{caller: caller_uri, caps: caps, reply: :sync}
    }

    case Esr.Invocation.dispatch(inv) do
      {:ok, _} -> :ok
      :ok -> :ok
      {:error, _} = err -> err
    end
  end

  # PR 27: send a Feishu text back to the source chat when ESR
  # dispatch can't proceed, so the human sees the failure instead of
  # waiting in silence. THUMBSDOWN react paired with the explanation
  # text mirrors the existing :pending → THUMBSDOWN pattern: emoji
  # for at-a-glance status, text for the "why."
  defp send_dispatch_error(chat_id, message_id, text) do
    Task.start(fn ->
      case Client.send_text(chat_id, text) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning("Feishu send_text (dispatch_error) failed: #{inspect(reason)}")
      end
    end)

    react_safe(message_id, "THUMBSDOWN")
    :ok
  end

  # Best-effort react — failures are non-fatal (network blip on
  # Feishu side shouldn't escalate). `message_id` may be nil for
  # event types without one.
  defp react_safe(nil, _), do: :ok

  # Allen 2026-05-17: react latency was ~seconds because chat/send
  # fan-out fired sync HTTP calls (feishu echo) before this line.
  # Push react into a Task so the user sees ack immediately while
  # ESR is still finishing the fan-out work.
  defp react_safe(message_id, emoji) do
    Task.start(fn ->
      case Client.react(message_id, emoji) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.debug("Feishu react #{emoji} on #{message_id} failed: #{inspect(reason)}")
      end
    end)

    :ok
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
