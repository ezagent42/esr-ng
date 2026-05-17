defmodule Esr.CCEvents do
  @moduledoc """
  CC-side error reporting (Phase 4-plus follow-up, 2026-05-17).

  Path: CC hook → HTTP POST /api/cc-events → controller → `report/1` →
  (a) PubSub broadcast on `cc_events:stream` for live operator surfaces,
  (b) telemetry emit so the event also lands in the audit log + DB.

  **Why not go through Invocation?** The hook fires when the CC agent
  itself is unreachable — auth expired, keychain locked, network
  partition. Routing the report through `Esr.Invocation.dispatch` would
  depend on the very agent that's broken. The endpoint deliberately
  bypasses the dispatch path so operator visibility survives agent
  failure.

  **Trust boundary**: no auth on the endpoint — same as the existing
  `/api/cc-bridge/announce` endpoint (network-level trust). The hook
  may fire before any CC-side auth is valid; requiring auth here would
  block the very scenario we're trying to surface.
  """

  @topic "cc_events:stream"

  @allowed_levels ~w(info warning error)

  @doc "PubSub topic LV surfaces subscribe to."
  def topic, do: @topic

  @doc """
  Validate + normalize + broadcast a CC event.

  Returns `{:ok, event_map}` or `{:error, reason}` for the controller to
  shape into a 200 / 422 response.
  """
  @spec report(map()) :: {:ok, map()} | {:error, atom()}
  def report(params) when is_map(params) do
    with {:ok, bridge_id} <- fetch_string(params, "bridge_id"),
         {:ok, level} <- fetch_level(params),
         {:ok, type} <- fetch_string(params, "type"),
         {:ok, text} <- fetch_string(params, "text") do
      event = %{
        bridge_id: bridge_id,
        level: level,
        type: type,
        text: text,
        at: DateTime.utc_now()
      }

      Phoenix.PubSub.broadcast(EsrCore.PubSub, @topic, {:cc_event, event})

      :telemetry.execute(
        [:esr, :cc_bridge, :event],
        %{count: 1},
        Map.put(event, :reported_at, event.at)
      )

      {:ok, event}
    end
  end

  defp fetch_string(params, key) do
    case Map.get(params, key) do
      s when is_binary(s) and byte_size(s) > 0 -> {:ok, s}
      _ -> {:error, {:missing_field, key}}
    end
  end

  defp fetch_level(params) do
    case Map.get(params, "level") do
      l when l in @allowed_levels -> {:ok, l}
      _ -> {:error, {:invalid_level, "must be info/warning/error"}}
    end
  end
end
