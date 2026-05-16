defmodule EsrWebLiveview.Admin.SessionsSidebar do
  @moduledoc """
  Left sidebar: sessions list + new-session form + floating-agent picker.
  Stateless — parent (AdminLive) owns assigns and event handlers.
  """

  use Phoenix.Component

  attr :sessions, :list, required: true
  attr :current_session_uri, URI, required: true
  attr :floating_agents, :list, required: true
  attr :new_session_form, :map, required: true

  def sessions_sidebar(assigns) do
    ~H"""
    <aside id="sessions-sidebar" style="border-right: 1px solid #eaeef2; padding-right: 16px;">
      <h3 style="font-size: 14px; font-weight: 500; margin: 0 0 8px 0;">Sessions</h3>
      <ul id="sessions-list" style="list-style: none; padding: 0; margin: 0;">
        <li :for={uri <- @sessions} style="margin-bottom: 4px;">
          <button
            type="button"
            phx-click="switch_session"
            phx-value-session_uri={URI.to_string(uri)}
            style={session_button_style(URI.to_string(uri) == URI.to_string(@current_session_uri))}
          >
            {URI.to_string(uri)}
          </button>
        </li>
      </ul>

      <div id="new-session-form" style="margin-top: 12px; padding-top: 12px; border-top: 1px solid #eaeef2;">
        <.form for={@new_session_form} phx-submit="create_session">
          <label style="display: block; font-size: 11px; color: #57606a;" for="new_session_short_name">+ New session</label>
          <input
            type="text"
            name="new_session[short_name]"
            id="new_session_short_name"
            placeholder="architect-review"
            style="width: 100%; padding: 4px 6px; margin-top: 2px; font-size: 12px; border: 1px solid #d1d5da; border-radius: 4px;"
          />
          <button
            type="submit"
            style="margin-top: 4px; width: 100%; padding: 4px; font-size: 11px; background: white; color: #0969da; border: 1px solid #0969da; border-radius: 4px; cursor: pointer;"
          >
            Create
          </button>
        </.form>
      </div>

      <div id="floating-agents" :if={@floating_agents != []} style="margin-top: 16px; padding-top: 12px; border-top: 1px solid #eaeef2;">
        <h4 style="font-size: 11px; color: #57606a; font-weight: 500; margin: 0 0 6px 0;">Floating agents</h4>
        <div :for={agent <- @floating_agents} style="margin-bottom: 8px; padding: 4px; border: 1px dashed #d1d5da; border-radius: 4px; font-size: 11px;">
          <div style="font-family: monospace;">{agent}</div>
          <form phx-change="add_agent_to_session" style="margin-top: 2px;">
            <input type="hidden" name="agent_uri" value={agent} />
            <select
              name="session_uri"
              style="width: 100%; font-size: 10px; padding: 2px;"
            >
              <option value="">Add to session…</option>
              <option :for={s <- @sessions} value={URI.to_string(s)}>{URI.to_string(s)}</option>
            </select>
          </form>
        </div>
      </div>
    </aside>
    """
  end

  defp session_button_style(true) do
    "width: 100%; text-align: left; padding: 6px 8px; background: #0969da; color: white; border: none; border-radius: 4px; cursor: pointer; font-family: monospace; font-size: 11px;"
  end

  defp session_button_style(false) do
    "width: 100%; text-align: left; padding: 6px 8px; background: white; color: #0969da; border: 1px solid #d1d5da; border-radius: 4px; cursor: pointer; font-family: monospace; font-size: 11px;"
  end
end
