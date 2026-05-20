defmodule EzagentWeb.WorkspaceSwitchController do
  @moduledoc """
  Workspace switcher endpoint.

  Per SPEC v3 §6.4 amendment (Allen 2026-05-21): workspace switch is
  NOT an in-place context swap. Entity URIs are workspace-bound
  (3-segment: `entity://<type>/<workspace>/<name>`), so switching
  workspace = switching entity = must re-authenticate.

  Flow:

  1. User picks another workspace from the top-left dropdown.
  2. Browser POSTs `/workspaces/switch` with `workspace=<target>` +
     CSRF token.
  3. This controller validates the target exists in
     `Ezagent.Workspace.Store`.
  4. On success: clears BOTH `:current_entity_uri` and
     `:current_workspace_uri` from the session, then redirects to
     `/login?workspace=<target>` with the workspace pre-filled in the
     login form (so the bare-handle path canonicalizes into the
     target workspace).
  5. On unknown workspace: redirects back to `/sessions` with a flash
     error (no auth change — current session stays intact).

  Why not a LV action / phx-click handler: this MUST mutate the
  session cookie + clear-session behavior, which only HTTP plug
  controllers can do reliably. LV-side `redirect/2` to the same URL
  would not rotate the cookie.
  """
  use EzagentWeb, :controller

  alias EzagentWeb.SessionPrincipal

  def switch(conn, %{"workspace" => target_workspace})
      when is_binary(target_workspace) and target_workspace != "" do
    case Ezagent.Workspace.Store.get_by_name(target_workspace) do
      nil ->
        conn
        |> put_flash(:error, "Unknown workspace: " <> target_workspace)
        |> redirect(to: ~p"/sessions")

      _ws ->
        conn
        |> SessionPrincipal.clear()
        |> put_flash(:info, "Sign in to workspace " <> target_workspace <> ".")
        |> redirect(to: "/login?workspace=" <> URI.encode(target_workspace))
    end
  end

  def switch(conn, _params) do
    conn
    |> put_flash(:error, "Missing workspace parameter.")
    |> redirect(to: ~p"/sessions")
  end
end
