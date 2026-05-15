defmodule EsrWeb.HealthController do
  @moduledoc """
  Liveness probe. Returns 200 + `{"status":"ok"}` if the BEAM node is up
  enough to serve HTTP. Does NOT exercise the ESR dispatch path — it is a
  plain controller action, not an Invocation (Phase 0 has no dispatch path).
  """
  use EsrWeb, :controller

  def index(conn, _params) do
    json(conn, %{status: "ok"})
  end
end
