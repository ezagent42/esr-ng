defmodule EsrWeb.CcBridgeAnnounceController do
  @moduledoc """
  Phase 1 v1_prototype announce endpoint.

  POST `/api/cc-bridge/announce`

  Body: `{"bridge_id": "...", "claude_info": {...}, "tools": [...]}`

  Records the bridge as connected via
  `Esr.Bridge.V1Prototype.Server.register/2`. The server broadcasts on
  `esr:bridge_v1:events` and LV /admin updates in real time.

  ## Phase 5 replacement

  The Phase 5 esr_plugin_cc_channel will use a Phoenix Channel /
  WebSocket join handshake instead of HTTP POST, with full CapBAC
  + session binding. This endpoint disappears entirely in Phase 5.
  """

  use Phoenix.Controller, formats: [:json]

  def announce(conn, params) do
    bridge_id = params["bridge_id"] || generated_fallback_id()

    info =
      %{
        claude_info: Map.get(params, "claude_info", %{}),
        tools: Map.get(params, "tools", []),
        remote_ip: format_remote_ip(conn.remote_ip)
      }

    :ok = Esr.Bridge.V1Prototype.Server.register(bridge_id, info)

    json(conn, %{ok: true, bridge_id: bridge_id})
  end

  def disconnect(conn, %{"bridge_id" => bridge_id}) do
    :ok = Esr.Bridge.V1Prototype.Server.unregister(bridge_id)
    json(conn, %{ok: true, bridge_id: bridge_id})
  end

  @doc """
  SSE endpoint the Python bridge subscribes to. Subscribes to the
  per-bridge to_claude Phoenix.PubSub topic and streams each
  `{:to_claude, %{content, meta}}` event as one SSE `data:` block.

  Holds the connection open indefinitely. The bridge process closes
  the connection when claude exits (stdin EOF triggers process exit
  triggers SSE socket close).
  """
  def events_sse(conn, %{"bridge_id" => bridge_id}) do
    :ok = Phoenix.PubSub.subscribe(EsrCore.PubSub, "esr:bridge_v1:to_claude:#{bridge_id}")

    conn =
      conn
      |> Plug.Conn.put_resp_header("content-type", "text/event-stream")
      |> Plug.Conn.put_resp_header("cache-control", "no-cache")
      |> Plug.Conn.put_resp_header("connection", "keep-alive")
      |> Plug.Conn.send_chunked(200)

    # Initial keep-alive comment so curl shows something immediately
    # and proxies don't close the idle connection.
    {:ok, conn} = Plug.Conn.chunk(conn, ": connected\n\n")

    sse_loop(conn)
  end

  defp sse_loop(conn) do
    receive do
      {:to_claude, payload} ->
        line = "data: " <> Jason.encode!(payload) <> "\n\n"

        case Plug.Conn.chunk(conn, line) do
          {:ok, conn} -> sse_loop(conn)
          {:error, _} -> conn
        end
    after
      30_000 ->
        # Keepalive comment to detect dead sockets.
        case Plug.Conn.chunk(conn, ": keepalive\n\n") do
          {:ok, conn} -> sse_loop(conn)
          {:error, _} -> conn
        end
    end
  end

  @doc """
  Python bridge POSTs here when claude calls its `reply` tool. We
  forward to the Server's record_reply so LV can render it.
  """
  def reply(conn, %{"bridge_id" => bridge_id, "text" => text})
      when is_binary(bridge_id) and is_binary(text) do
    :ok = Esr.Bridge.V1Prototype.Server.record_reply(bridge_id, text)
    json(conn, %{ok: true})
  end

  defp generated_fallback_id do
    "bridge-#{:crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)}"
  end

  defp format_remote_ip({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"
  defp format_remote_ip(other), do: inspect(other)
end
