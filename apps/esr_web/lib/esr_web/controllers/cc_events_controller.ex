defmodule EsrWeb.CcEventsController do
  @moduledoc """
  CC hook error reporting endpoint (Phase 4-plus follow-up).

  `POST /api/cc-events`

  Body (JSON):
      {
        "bridge_id": "cc-bridge-laptop-1",
        "level": "error",
        "type": "auth_expired",
        "text": "Not logged in · Please run /login"
      }

  Returns 200 + `{"status": "ok"}` on success, 422 + `{"error": ...}` on
  validation failure.

  **No auth on this endpoint by design** — the hook fires when the CC
  agent itself is broken (auth expired, network partition). Requiring
  auth here would block the very signal it's trying to surface. Trust
  is at the network boundary, same as the existing
  `/api/cc-bridge/announce` endpoint.
  """
  use EsrWeb, :controller

  def report(conn, params) do
    case Esr.CCEvents.report(params) do
      {:ok, _event} ->
        conn |> put_status(:ok) |> json(%{status: "ok"})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: inspect(reason)})
    end
  end
end
