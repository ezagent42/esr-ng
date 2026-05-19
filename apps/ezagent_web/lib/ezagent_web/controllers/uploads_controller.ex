defmodule EzagentWeb.UploadsController do
  @moduledoc """
  Serves files uploaded via the chat compose UI (PR-B).

  Files live under `$EZAGENT_HOME/<profile>/uploads/` and are named
  `<uuid>-<original-name>`. The controller takes only the filename
  segment from the URL — directory traversal (`..`) is blocked at
  the router via `Plug.Static`-style sanitization here.

  Auth: the route is mounted inside the `RequireUser` pipeline (same
  as the rest of /admin/*). Anyone reaching this controller has a
  signed-in session.
  """

  use EzagentWeb, :controller

  alias Ezagent.Home

  def show(conn, %{"filename" => filename}) do
    safe = Path.basename(filename)

    case safe do
      ^filename when safe != "" and safe != "." and safe != ".." ->
        full = Path.join(Home.path("uploads"), safe)

        if File.regular?(full) do
          send_download(conn, {:file, full}, filename: original_name(safe))
        else
          conn
          |> put_status(:not_found)
          |> text("upload not found")
        end

      _ ->
        conn
        |> put_status(:bad_request)
        |> text("invalid filename")
    end
  end

  defp original_name(<<_uuid::binary-size(36), "-", rest::binary>>), do: rest
  defp original_name(other), do: other
end
