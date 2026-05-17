defmodule EsrWebLiveview.AgentDetailLive do
  @moduledoc """
  Phase 5 PR 3: per-agent PTY status detail at `/admin/agents/:uri`.

  Path segment is URI-encoded `agent://...`. Auto-refresh every 2s
  so operator sees stdout flowing without a manual reload.

  Restart button stops the PtyServer; DynamicSupervisor restarts it
  per `:permanent` restart spec.
  """
  use Phoenix.LiveView
  import Phoenix.Component

  @impl true
  def mount(%{"uri" => encoded_uri}, _session, socket) do
    case parse_agent_uri(encoded_uri) do
      {:ok, agent_uri} ->
        if connected?(socket) do
          # 2-second polling matches operator scan rate without
          # hammering :sys.get_state on a busy PTY.
          :timer.send_interval(2000, :refresh)
        end

        {:ok,
         socket
         |> assign(:not_found, false)
         |> assign(:agent_uri, agent_uri)
         |> assign(:flash_error, nil)
         |> assign(:status, load_status(agent_uri))}

      _ ->
        {:ok, assign(socket, :not_found, true) |> assign(:bad_uri, encoded_uri)}
    end
  end

  defp parse_agent_uri(encoded) do
    decoded = URI.decode_www_form(encoded)

    case URI.new(decoded) do
      {:ok, %URI{scheme: "agent"} = uri} -> {:ok, uri}
      _ -> :error
    end
  end

  defp load_status(agent_uri) do
    case Esr.PluginCcPty.PtyServer.find_by_agent_uri(agent_uri) do
      {:ok, pid} -> {:alive, Esr.PluginCcPty.PtyServer.status(pid)}
      :error -> :not_found
    end
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, assign(socket, :status, load_status(socket.assigns.agent_uri))}
  end

  @impl true
  def handle_event("restart", _params, socket) do
    case Esr.PluginCcPty.PtyServer.find_by_agent_uri(socket.assigns.agent_uri) do
      {:ok, pid} ->
        # Supervisor terminates → restart via :permanent restart spec.
        # GenServer.stop(:normal) would suppress restart; use :shutdown
        # to signal "restart-please, no crash logged".
        Process.exit(pid, :shutdown)

        # Allow restart to settle before re-reading.
        Process.send_after(self(), :refresh, 500)

        {:noreply,
         socket
         |> assign(:status, :not_found)
         |> assign(:flash_error, nil)}

      :error ->
        {:noreply, assign(socket, :flash_error, "no live PtyServer for this agent")}
    end
  end

  @impl true
  def render(%{not_found: true} = assigns) do
    ~H"""
    <div style="max-width: 800px; margin: 0 auto; padding: 24px; font-family: -apple-system, sans-serif;">
      <h1>Agent URI invalid</h1>
      <p><code>{@bad_uri}</code></p>
      <p><a href="/admin/agents" style="color: #0969da;">← Agents</a></p>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div style="max-width: 1000px; margin: 0 auto; padding: 24px; font-family: -apple-system, sans-serif;">
      <header>
        <h1 style="font-size: 22px; font-weight: 600;">
          Agent: <code>{URI.to_string(@agent_uri)}</code>
        </h1>
        <p style="font-size: 13px; color: #666;">
          <a href="/admin/agents" style="color: #0969da;">← Agents</a>
          <span style="margin-left: 16px;">auto-refresh every 2s</span>
        </p>
      </header>

      <p :if={@flash_error} style="color: #cf222e; font-size: 13px; margin-top: 12px;">
        {@flash_error}
      </p>

      <%= case @status do %>
        <% :not_found -> %>
          <section style="margin-top: 24px; padding: 16px; border: 1px solid #d1d5da; border-radius: 6px;">
            <h2 style="font-size: 14px; color: #cf222e;">Not running</h2>
            <p style="font-size: 13px;">
              No live PtyServer for this URI. If you just clicked Restart, wait a moment.
              Otherwise, add a cc.pty template for this agent_uri in a Workspace.
            </p>
          </section>
        <% {:alive, s} -> %>
          <section style="margin-top: 24px; padding: 16px; border: 1px solid #d1d5da; border-radius: 6px;">
            <h2 style="font-size: 14px; font-weight: 500; margin: 0 0 12px 0;">Status</h2>
            <table style="width: 100%; font-size: 13px;">
              <tbody>
                <tr><td style="padding: 3px 0; width: 200px; color: #57606a;">os_pid</td><td style="font-family: monospace;">{s.os_pid || "—"}</td></tr>
                <tr><td style="padding: 3px 0; color: #57606a;">cwd</td><td style="font-family: monospace; font-size: 11px;">{s.cwd}</td></tr>
                <tr><td style="padding: 3px 0; color: #57606a;">running</td><td style={if s.running, do: "color: #1f883d; font-weight: 600;", else: "color: #cf222e;"}>{if s.running, do: "yes", else: "no"}</td></tr>
                <tr><td style="padding: 3px 0; color: #57606a;">test_mode</td><td>{s.test_mode}</td></tr>
                <tr><td style="padding: 3px 0; color: #57606a;">dev_channels_confirmed</td><td>{s.dev_channels_confirmed}</td></tr>
                <tr><td style="padding: 3px 0; color: #57606a;">buffer_bytes</td><td>{s.buffer_bytes}</td></tr>
              </tbody>
            </table>

            <div style="margin-top: 12px; display: flex; gap: 8px;">
              <a
                href={"/admin/agents/#{URI.encode_www_form(URI.to_string(@agent_uri))}/terminal"}
                style="padding: 6px 14px; background: #1f883d; color: white; border: none; border-radius: 4px; cursor: pointer; font-size: 12px; text-decoration: none;"
              >📺 Open terminal (xterm)</a>
              <button
                type="button"
                phx-click="restart"
                id="restart-btn"
                style="padding: 6px 14px; background: white; color: #cf222e; border: 1px solid #cf222e; border-radius: 4px; cursor: pointer; font-size: 12px;"
                data-confirm="Restart PtyServer for this agent? (supervisor will respawn)"
              >Restart</button>
            </div>
          </section>

          <section :if={s.recent_output != []} style="margin-top: 24px; padding: 16px; border: 1px solid #d1d5da; border-radius: 6px; background: #1e1e1e; color: #d4d4d4;">
            <h2 style="font-size: 14px; font-weight: 500; margin: 0 0 8px 0; color: #d4d4d4;">Recent PTY output (last 50 lines)</h2>
            <pre style="font-family: 'SF Mono', Menlo, monospace; font-size: 11px; white-space: pre-wrap; margin: 0; max-height: 360px; overflow-y: auto;"><%= for line <- s.recent_output do %>{line}
<% end %></pre>
          </section>
      <% end %>
    </div>
    """
  end
end
