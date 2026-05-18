defmodule EzagentPluginLiveview.AgentsLive do
  @moduledoc """
  Phase 5 PR 3: list of live PTY-managed agents.

  Currently shows cc-pty agents (the only PTY-managed Kind in Phase 4.5).
  Future PTY-managed Kinds register via the same pattern.

  Click an agent → `/admin/agents/<uri-encoded>` for detail (PR 3
  AgentDetailLive).
  """

  use Phoenix.LiveView
  import Phoenix.Component

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:agents, list_live_agents())
     |> assign(:flash_error, nil)}
  end

  defp list_live_agents do
    if Code.ensure_loaded?(Esr.PluginCcPty.PtyServer) do
      Esr.PluginCcPty.PtyServer.list_agents()
    else
      []
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div style="max-width: 1000px; margin: 0 auto; padding: 24px; font-family: -apple-system, sans-serif;">
      <header>
        <h1 style="font-size: 22px; font-weight: 600;">Agents (PTY-managed)</h1>
        <p style="font-size: 13px; color: #666;">
          Live PtyServer children. cc-pty agents launched via cc.pty Template Class appear here.
          <a href="/admin" style="margin-left: 16px; color: #0969da;">← /admin</a>
        </p>
      </header>

      <section style="margin-top: 24px;">
        <p :if={@agents == []} id="agents-empty" style="font-size: 13px; color: #57606a; font-style: italic;">
          No live PTY agents. Add a cc.pty template to a Workspace.
        </p>

        <table :if={@agents != []} id="agents-table" style="width: 100%; font-size: 13px; border-collapse: collapse;">
          <thead>
            <tr style="border-bottom: 1px solid #d1d5da;">
              <th style="text-align: left; padding: 6px 0;">agent_uri</th>
              <th style="text-align: left;">os_pid</th>
              <th style="text-align: left;">status</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={agent <- @agents} style="border-bottom: 1px solid #eee;">
              <td style="padding: 4px 0; font-family: monospace;">{URI.to_string(agent.agent_uri)}</td>
              <td style="font-family: monospace; font-size: 11px;">{agent.os_pid || "—"}</td>
              <td style="color: #1f883d; font-weight: 600;">running</td>
              <td>
                <a
                  href={"/admin/agents/#{uri_to_path_seg(agent.agent_uri)}"}
                  style="color: #0969da; font-size: 12px;"
                >detail →</a>
              </td>
            </tr>
          </tbody>
        </table>
      </section>
    </div>
    """
  end

  defp uri_to_path_seg(%URI{} = uri),
    do: uri |> URI.to_string() |> URI.encode_www_form()
end
