defmodule EzagentWeb.LiveAuth do
  @moduledoc """
  LiveView `on_mount` hook that gates admin LVs on a logged-in user.

  Plug `RequireUser` already runs on the HTTP dead-render path
  (`live` macro hits `mount/3` once before the WS upgrade), so for
  initial connects this is a belt-and-suspenders check. But on a
  fresh WS reconnect with an expired/missing session, only the
  on_mount hook protects the LV — without it, an LV's `mount/3`
  would receive `session = %{}` and would historically fall back to
  `Ezagent.Entity.User.admin_uri()` / `admin_caps()` (security bug
  pre-PR #123).

  ## Wiring

  Mounted via `live_session` block in the router:

      live_session :require_user, on_mount: {EzagentWeb.LiveAuth, :require_user} do
        live "/admin", EzagentPluginLiveview.AdminLive
        # ...
      end

  ## Effect

  On successful auth, sets `socket.assigns.current_user_uri` to a
  `%URI{}`. LVs can read this directly instead of re-parsing from
  the session map (and instead of falling back to admin if it's
  missing — that fallback is now deleted across all 5 LVs).

  On failure (no `current_user_uri` in session), redirects to
  `/login` and halts mount. Public exposure safe.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [redirect: 2]

  def on_mount(:require_user, _params, session, socket) do
    case session["current_user_uri"] do
      nil ->
        {:halt, redirect(socket, to: "/login")}

      uri_str when is_binary(uri_str) ->
        {:cont, assign(socket, :current_user_uri, URI.parse(uri_str))}
    end
  end
end
