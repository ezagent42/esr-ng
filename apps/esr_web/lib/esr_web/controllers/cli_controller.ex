defmodule EsrWeb.CliController do
  @moduledoc """
  POST /api/cli/exec — server-side CLI entry point.

  Post-Phase-5 pivot (Allen 2026-05-17). `mix esr` is a thin shell:
  it POSTs `{argv: [...]}` here; this controller calls
  `EsrCLI.Exec.exec(argv)` IN THE RUNNING SERVER — same BEAM as LV,
  same KindRegistry, same Repo, same audit telemetry.

  Restores CLI ↔ LV runtime isomorphism (Roadmap §1.4): the CLI just
  forwards what the user typed; the server does the actual work.

  ## Request

      POST /api/cli/exec
      Content-Type: application/json
      {"argv": ["session", "join", "--session", "main", "--member", "agent://cc-demo"]}

  ## Response

      200 OK
      {"output": "ok\\n", "exit_code": 0}

  ## Auth

  No session-cookie auth — `mix esr` runs from operator's shell
  without cookies. Trust at the network boundary (same as
  `/api/cc-bridge/announce` etc).

  Future: token-based caps so non-admin CLI users still go through
  CapBAC. v1 trusts local network.
  """
  use EsrWeb, :controller

  def exec(conn, %{"argv" => argv}) when is_list(argv) do
    result = EsrCLI.Exec.exec(argv)
    conn |> put_status(:ok) |> json(result)
  end

  def exec(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{output: "error: missing argv field\n", exit_code: 2})
  end
end
