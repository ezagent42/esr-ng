defmodule EzagentWeb.WorkspaceSwitchHTML do
  @moduledoc """
  HTML rendering for `EzagentWeb.WorkspaceSwitchController` — Phase 9
  PR-8 (SPEC v3 §6.4 amendment 3).

  Currently one template: `denied.html.heex` shown when a regular
  (non-system-member) user attempts to switch into a workspace they
  don't belong to. The page offers a "Sign in to <ws>" link which
  POSTs to /logout with `return_to=/login?workspace=<ws>` so the
  user consciously chooses to lose the current session.
  """
  use EzagentWeb, :html

  embed_templates "workspace_switch_html/*"

  @doc """
  Build the /logout URL whose `return_to` carries the user back to
  the login form with the target workspace pre-filled.

  Output shape: `/logout?return_to=%2Flogin%3Fworkspace%3D<ws>`. The
  `return_to` value is URI-encoded as a single query param so it
  survives Plug's param parser; the SessionController.delete handler
  validates it's a local path before redirecting.
  """
  @spec logout_to_login_path(String.t()) :: String.t()
  def logout_to_login_path(workspace_name) when is_binary(workspace_name) do
    return_to = "/login?workspace=" <> URI.encode_www_form(workspace_name)
    "/logout?return_to=" <> URI.encode_www_form(return_to)
  end
end
