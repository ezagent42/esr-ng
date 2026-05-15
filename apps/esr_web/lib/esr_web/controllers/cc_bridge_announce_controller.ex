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

  defp generated_fallback_id do
    "bridge-#{:crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)}"
  end

  defp format_remote_ip({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"
  defp format_remote_ip(other), do: inspect(other)
end
