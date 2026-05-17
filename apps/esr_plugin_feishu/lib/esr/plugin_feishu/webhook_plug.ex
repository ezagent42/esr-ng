defmodule EsrPluginFeishu.WebhookPlug do
  @moduledoc """
  Phase 5 PR 6 — Feishu webhook receiver.

  Two payload shapes Feishu sends:
  1. **URL verification challenge** (`{type: "url_verification", challenge: "X"}`)
     → respond `{challenge: "X"}` so Feishu validates the endpoint
  2. **Event callback** (`{schema: "2.0", header: {...}, event: {...}}`)
     → if event is a message in a bound chat, dispatch into the session

  ## Route registration

  esr_web's router.ex adds:
      forward "/api/feishu/webhook", EsrPluginFeishu.WebhookPlug

  This is the ONLY touch this plugin makes to esr_web — explicitly
  allowed per SPEC v2 north star clause ("beyond webhook route
  registration").

  ## Auth

  Webhook is unauthenticated at the network level (Feishu can't carry
  ESR session cookies). Future hardening: validate `Encrypt-Key` header
  signature when `verification_token` is configured.
  """
  import Plug.Conn
  require Logger

  def init(opts), do: opts

  def call(%Plug.Conn{method: "POST"} = conn, _opts) do
    # Plug.Parsers (JSON) runs before forwarded routes, so the body has
    # already been consumed. Use conn.body_params (already a map).
    # Fallback to re-reading raw bytes for clients that bypass parsers.
    payload =
      cond do
        is_map(conn.body_params) and conn.body_params != %{} and
            not match?(%Plug.Conn.Unfetched{}, conn.body_params) ->
          {:ok, conn.body_params}

        true ->
          case read_body(conn) do
            {:ok, body, _} when is_binary(body) and body != "" -> Jason.decode(body)
            _ -> {:error, :empty_body}
          end
      end

    case payload do
      {:ok, %{"type" => "url_verification", "challenge" => challenge}} ->
        Logger.info("EsrPluginFeishu webhook: URL verification challenge")
        conn |> put_resp_content_type("application/json") |> send_resp(200, Jason.encode!(%{challenge: challenge}))

      {:ok, %{"schema" => "2.0", "header" => header, "event" => event}} ->
        handle_event(header, event)
        conn |> put_resp_content_type("application/json") |> send_resp(200, "{}")

      {:ok, other} ->
        Logger.warning("EsrPluginFeishu webhook: unrecognized payload keys: #{inspect(Map.keys(other))}")
        send_resp(conn, 200, "{}")

      {:error, reason} ->
        Logger.warning("EsrPluginFeishu webhook: bad payload: #{inspect(reason)}")
        send_resp(conn, 400, "bad payload")
    end
  end

  def call(conn, _opts), do: send_resp(conn, 405, "method not allowed")

  defp handle_event(_header, %{"message" => msg, "sender" => sender}) do
    chat_id = Map.get(msg, "chat_id")
    message_id = Map.get(msg, "message_id")
    body = build_message_body(msg, message_id)

    cond do
      is_nil(chat_id) ->
        Logger.warning("Feishu webhook: missing chat_id")

      body.text == "" and body.attachments == [] ->
        Logger.debug(
          "Feishu webhook: empty body for message_type=#{inspect(Map.get(msg, "message_type"))} — drop"
        )

      true ->
        case lookup_session_for_chat(chat_id) do
          {:ok, session_uri} ->
            user_uri = sender_to_uri(sender)
            dispatch_into_session(session_uri, user_uri, body)

          :error ->
            Logger.info("Feishu webhook: no binding for chat_id #{chat_id} (drop)")
        end
    end
  end

  defp handle_event(_header, other),
    do: Logger.debug("Feishu webhook: unhandled event shape: #{inspect(Map.keys(other))}")

  # Phase 6 PR 14: build message body that always carries the
  # message_type, even when ESR can't natively render it. Attachments
  # are tagged with type + name + size + the Feishu file_key so
  # downstream (CC bridge, Feishu outbound) has enough metadata to
  # describe — and later download — the resource.
  #
  # Allen 2026-05-17: "理论上应该将所有信息都传入channel，即使没办法
  # 处理，至少让cc/user知道尝试传了什么type的信息".
  # Phase 6 PR 14: test-only access to the message-body builder.
  # NOT meant for production callers — webhook flow uses the private
  # build_message_body via handle_event.
  @doc false
  def __build_message_body_for_test__(msg) do
    build_message_body(msg, Map.get(msg, "message_id"))
  end

  defp build_message_body(msg, message_id) do
    msg_type = Map.get(msg, "message_type", "unknown")
    content = decode_content(Map.get(msg, "content"))

    case msg_type do
      "text" ->
        %{text: Map.get(content, "text", ""), attachments: []}

      "image" ->
        %{
          text: "",
          attachments: [
            attachment(:image, %{
              "file_key" => Map.get(content, "image_key"),
              "name" => "image-" <> short_id(message_id) <> ".jpg",
              "message_id" => message_id,
              "mime" => "image/jpeg"
            })
          ]
        }

      "file" ->
        %{
          text: "",
          attachments: [
            attachment(:file, %{
              "file_key" => Map.get(content, "file_key"),
              "name" => Map.get(content, "file_name", "file-" <> short_id(message_id)),
              "size" => Map.get(content, "file_size"),
              "message_id" => message_id
            })
          ]
        }

      "audio" ->
        %{
          text: "",
          attachments: [
            attachment(:audio, %{
              "file_key" => Map.get(content, "file_key"),
              "name" => "audio-" <> short_id(message_id),
              "duration" => Map.get(content, "duration"),
              "message_id" => message_id
            })
          ]
        }

      "media" ->
        %{
          text: "",
          attachments: [
            attachment(:video, %{
              "file_key" => Map.get(content, "file_key"),
              "name" => "video-" <> short_id(message_id),
              "duration" => Map.get(content, "duration"),
              "message_id" => message_id
            })
          ]
        }

      other ->
        # Unknown type: pass through as text breadcrumb so CC/user
        # sees "[unsupported feishu message_type=sticker]" instead of
        # silent drop.
        %{
          text: "[feishu message_type=#{other} unhandled — content keys: #{inspect(Map.keys(content))}]",
          attachments: []
        }
    end
  end

  defp decode_content(content) when is_binary(content) do
    case Jason.decode(content) do
      {:ok, m} when is_map(m) -> m
      _ -> %{}
    end
  end

  defp decode_content(_), do: %{}

  defp attachment(type, raw) do
    %{
      type: type,
      source: "feishu",
      file_key: Map.get(raw, "file_key"),
      message_id: Map.get(raw, "message_id"),
      name: Map.get(raw, "name"),
      mime: Map.get(raw, "mime"),
      size_bytes: Map.get(raw, "size"),
      duration: Map.get(raw, "duration")
    }
  end

  defp short_id(nil), do: "unknown"
  defp short_id(s) when is_binary(s), do: String.slice(s, -8, 8)

  # Phase 6 PR 14: best-effort attachment download. On success, augment
  # the attachment map with `:local_path`; on failure, log + keep
  # metadata only so the recipient still knows what type came through.
  defp maybe_download(%{file_key: nil} = att), do: att

  defp maybe_download(%{type: type, file_key: key, message_id: mid, name: name} = att)
       when is_binary(key) and is_binary(mid) do
    feishu_type = feishu_resource_type(type)

    case EsrPluginFeishu.Client.download_resource(mid, key, feishu_type, name) do
      {:ok, path} ->
        Map.put(att, :local_path, path)

      {:error, reason} ->
        Logger.warning("Feishu webhook: download #{type}/#{name} failed: #{inspect(reason)} — metadata-only forward")
        att
    end
  end

  defp maybe_download(att), do: att

  # Map our normalized type → Feishu resource ?type= query value.
  defp feishu_resource_type(:image), do: "image"
  defp feishu_resource_type(:file), do: "file"
  defp feishu_resource_type(:audio), do: "file"
  defp feishu_resource_type(:video), do: "file"
  defp feishu_resource_type(_), do: "file"

  # Reverse lookup chat_id → session_uri via routing_rules table.
  # Plan B (2026-05-17) made Feishu binding a routing rule:
  # `in_session(session_uri) → [feishu://<chat_id>]`. Inbound webhook
  # needs the inverse direction: given chat_id, find the session.
  # We scan MentionRouting rules for any whose receivers contain the
  # feishu URI, and pull session_uri out of the in_session matcher.
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

  defp sender_to_uri(%{"sender_id" => %{"open_id" => oid}}) when is_binary(oid),
    do: URI.parse("user://feishu/#{oid}")

  defp sender_to_uri(%{"sender_id" => %{"user_id" => uid}}) when is_binary(uid),
    do: URI.parse("user://feishu/#{uid}")

  defp sender_to_uri(_), do: URI.parse("user://feishu/unknown")

  defp dispatch_into_session(session_uri, user_uri, body) when is_map(body) do
    # Phase 6 PR 14: best-effort download of any feishu-source
    # attachments so we get a local path. If download fails (creds,
    # network), drop down to metadata-only — CC still sees the type
    # and name via the attachment hint text.
    body = Map.update(body, :attachments, [], fn list -> Enum.map(list, &maybe_download/1) end)
    msg = Esr.Message.new(user_uri, body)

    target = URI.parse("#{URI.to_string(session_uri)}/behavior/chat/send")

    inv = %Esr.Invocation{
      target: target,
      mode: :cast,
      args: %{message: msg},
      ctx: %{
        caller: user_uri,
        # Feishu users get no caps; chat/send is open per Phase 2 default.
        caps: MapSet.new(),
        reply: :ignore
      }
    }

    case Esr.Invocation.dispatch(inv) do
      {:ok, _} -> :ok
      :ok -> :ok
      {:error, reason} -> Logger.warning("Feishu inbound dispatch failed: #{inspect(reason)}")
    end
  end
end
