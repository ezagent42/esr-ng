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
    {:ok, body, conn} = read_body(conn)

    case Jason.decode(body) do
      {:ok, %{"type" => "url_verification", "challenge" => challenge}} ->
        Logger.info("EsrPluginFeishu webhook: URL verification challenge")
        conn |> put_resp_content_type("application/json") |> send_resp(200, Jason.encode!(%{challenge: challenge}))

      {:ok, %{"schema" => "2.0", "header" => header, "event" => event}} ->
        handle_event(header, event)
        conn |> put_resp_content_type("application/json") |> send_resp(200, "{}")

      {:ok, other} ->
        Logger.warning("EsrPluginFeishu webhook: unrecognized payload: #{inspect(other)}")
        send_resp(conn, 200, "{}")

      {:error, _} = err ->
        Logger.warning("EsrPluginFeishu webhook: bad JSON: #{inspect(err)}")
        send_resp(conn, 400, "bad json")
    end
  end

  def call(conn, _opts), do: send_resp(conn, 405, "method not allowed")

  defp handle_event(_header, %{"message" => msg, "sender" => sender}) do
    chat_id = Map.get(msg, "chat_id")
    text = extract_text(msg)

    cond do
      is_nil(chat_id) ->
        Logger.warning("Feishu webhook: missing chat_id")

      text == "" ->
        Logger.debug("Feishu webhook: non-text or empty message; skipping")

      true ->
        case lookup_session_for_chat(chat_id) do
          {:ok, session_uri} ->
            user_uri = sender_to_uri(sender)
            dispatch_into_session(session_uri, user_uri, text)

          :error ->
            Logger.info("Feishu webhook: no binding for chat_id #{chat_id} (drop)")
        end
    end
  end

  defp handle_event(_header, other),
    do: Logger.debug("Feishu webhook: unhandled event shape: #{inspect(Map.keys(other))}")

  defp extract_text(%{"message_type" => "text", "content" => content}) when is_binary(content) do
    case Jason.decode(content) do
      {:ok, %{"text" => t}} when is_binary(t) -> t
      _ -> ""
    end
  end

  defp extract_text(_), do: ""

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

  defp dispatch_into_session(session_uri, user_uri, text) do
    msg = Esr.Message.new(user_uri, %{text: text, attachments: []})

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
