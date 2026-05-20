defmodule EzagentWeb.LiveAuth do
  @moduledoc """
  LiveView `on_mount` hook that gates admin LVs on a logged-in entity.

  Plug `RequireEntity` already runs on the HTTP dead-render path
  (`live` macro hits `mount/3` once before the WS upgrade), so for
  initial connects this is a belt-and-suspenders check. But on a
  fresh WS reconnect with an expired/missing session, only the
  on_mount hook protects the LV — without it, an LV's `mount/3`
  would receive `session = %{}` and would historically fall back to
  `Ezagent.Entity.User.admin_uri()` / `admin_caps()` (security bug
  pre-PR #123).

  ## Wiring

  Mounted via `live_session` block in the router:

      live_session :require_entity, on_mount: {EzagentWeb.LiveAuth, :require_entity} do
        live "/admin", EzagentPluginLiveview.AdminLive
        # ...
      end

  ## Effect

  On successful auth, sets `socket.assigns.current_entity_uri` to a
  `%URI{}`. LVs can read this directly instead of re-parsing from
  the session map (and instead of falling back to admin if it's
  missing — that fallback is now deleted across all 5 LVs).

  On failure (no `current_entity_uri` in session), redirects to
  `/login` and halts mount. Public exposure safe.

  ## PR #142 rename

  Renamed from `:require_user` → `:require_entity` to reflect that
  the gated session may belong to any Entity (a human User OR an
  Agent acting via bearer token).

  ## PR #149 (S-8) hardening

  WS reconnect path now asserts the session URI parses to an
  `entity://` shape with `host in ["user", "agent"]`. A malformed
  or non-entity URI in the cookie redirects to `/login` instead of
  silently propagating into LV assigns. Same vigilance as PR #123:
  prevent any silent fallback to admin on reconnect.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [redirect: 2]

  def on_mount(:require_entity, _params, session, socket) do
    case session["current_entity_uri"] do
      nil ->
        {:halt, redirect(socket, to: "/login")}

      uri_str when is_binary(uri_str) ->
        case parse_entity_uri(uri_str) do
          {:ok, uri} ->
            {:cont,
             socket
             |> assign(:current_entity_uri, uri)
             |> assign(:is_admin?, admin?(uri))}

          :error ->
            # Malformed / non-entity URI → treat as unauthenticated.
            {:halt, redirect(socket, to: "/login")}
        end
    end
  end

  # Phase 8c follow-up (Allen 2026-05-20) — `is_admin?` was set in
  # admin_live's mount but not propagated to the other 12 LVs that
  # wrap IdeShell. Result: Admin link in avatar dropdown disappeared
  # when navigating to /profile or /settings even for admin users.
  # Setting it here on every LV in the `:require_entity` live_session
  # means avatar_menu reads it uniformly. assign_new in admin_live
  # still works (this fires first, admin_live's assign_new sees a
  # value and is a no-op).
  defp admin?(uri) do
    if Code.ensure_loaded?(Ezagent.Identity) and
         function_exported?(Ezagent.Identity, :admin?, 1) do
      Ezagent.Identity.admin?(uri)
    else
      false
    end
  end

  # PR #149 (S-8): accept entity://user/* and entity://agent/* uniformly.
  defp parse_entity_uri(uri_str) do
    case URI.new(uri_str) do
      {:ok, %URI{scheme: "entity", host: host, path: "/" <> name} = uri}
      when host in ["user", "agent"] and name != "" ->
        {:ok, uri}

      _ ->
        :error
    end
  end
end
