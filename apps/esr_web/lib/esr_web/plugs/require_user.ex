defmodule EsrWeb.Plugs.RequireUser do
  @moduledoc """
  Plug that bounces unauthenticated requests to `/login`.

  Per Phase 4-completion Spec 05 §A.2.3 — gates admin LV scopes.
  Public scopes (e.g. `/`) skip this plug.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, :current_user_uri) do
      nil ->
        conn
        |> redirect(to: "/login")
        |> halt()

      uri_str when is_binary(uri_str) ->
        assign(conn, :current_user_uri, URI.parse(uri_str))
    end
  end
end
