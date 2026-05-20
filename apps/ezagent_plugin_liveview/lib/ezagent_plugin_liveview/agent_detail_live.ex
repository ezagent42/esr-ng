defmodule EzagentPluginLiveview.AgentDetailLive do
  @moduledoc """
  Phase 5 PR 3: per-agent PTY status detail at `/identities/agents/:uri`.

  Path segment is URI-encoded `entity://agent/...`. Auto-refresh every 2s
  so operator sees stdout flowing without a manual reload.

  Restart button stops the PtyServer; DynamicSupervisor restarts it
  per `:permanent` restart spec.
  """
  use Phoenix.LiveView
  alias EzagentDomainUi.IdeShell
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
         |> assign(:status, load_status(agent_uri))
         |> assign(:bridge_entry, load_bridge_entry(agent_uri))}

      _ ->
        {:ok, assign(socket, :not_found, true) |> assign(:bad_uri, encoded_uri)}
    end
  end

  # PR #141 + #145: entity:// scheme; agent URIs are entity://agent/<flavor>_<name>.
  defp parse_agent_uri(encoded) do
    decoded = URI.decode_www_form(encoded)

    case URI.new(decoded) do
      {:ok, %URI{scheme: "entity", host: "agent", path: "/" <> name} = uri}
      when is_binary(name) and name != "" ->
        {:ok, uri}

      _ ->
        :error
    end
  end

  defp load_status(agent_uri) do
    case Ezagent.PluginCc.PtyServer.find_by_agent_uri(agent_uri) do
      {:ok, pid} -> {:alive, Ezagent.PluginCc.PtyServer.status(pid)}
      :error -> :not_found
    end
  end

  # Phase 8b §1.10 — CC Bridges (v2) panel moved here from admin_live.
  # Per-agent so the operator can see "is this agent's WS bridge live?"
  # while looking at the agent's other status data. Returns `nil` if
  # the BridgeRegistry has no entry for this agent (most likely cause:
  # local-pty agent that doesn't open a WS bridge).
  defp load_bridge_entry(agent_uri) do
    if Code.ensure_loaded?(EzagentPluginCc.BridgeRegistry) do
      EzagentPluginCc.BridgeRegistry.list_connected()
      |> Enum.find(fn {uri, _entry} ->
        URI.to_string(uri) == URI.to_string(agent_uri)
      end)
      |> case do
        {_uri, entry} -> entry
        nil -> nil
      end
    else
      nil
    end
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply,
     socket
     |> assign(:status, load_status(socket.assigns.agent_uri))
     |> assign(:bridge_entry, load_bridge_entry(socket.assigns.agent_uri))}
  end

  @impl true
  def handle_event("restart", _params, socket) do
    case Ezagent.PluginCc.PtyServer.find_by_agent_uri(socket.assigns.agent_uri) do
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
    assigns =
      assign_new(assigns, :current_entity_uri_str, fn ->
        URI.to_string(Map.get(assigns, :current_entity_uri) || URI.parse("entity://user/admin"))
      end)

    ~H"""
    <IdeShell.ide_shell
      current_entity_uri={@current_entity_uri_str}
      current_path="/identities/agents"
      status={%{agents_alive: 0, bridges: 0, debug_events: 0, version: "dev"}}
    >
      <:main_window>
        <div class="flex-1 overflow-auto px-6 py-6 text-zinc-900">
      <h1>Agent URI invalid</h1>
      <p><code>{@bad_uri}</code></p>
      <p><a href="/identities/agents" style="color: #0969da;">← Agents</a></p>
        </div>
      </:main_window>
    </IdeShell.ide_shell>
    """
  end

  def render(assigns) do
    assigns =
      assign_new(assigns, :current_entity_uri_str, fn ->
        URI.to_string(Map.get(assigns, :current_entity_uri) || URI.parse("entity://user/admin"))
      end)

    ~H"""
    <IdeShell.ide_shell
      current_entity_uri={@current_entity_uri_str}
      current_path="/identities/agents"
      status={%{agents_alive: 0, bridges: 0, debug_events: 0, version: "dev"}}
    >
      <:main_window>
        <div class="flex-1 overflow-auto px-6 py-6 text-zinc-900">
      <header>
        <h1 style="font-size: 22px; font-weight: 600;">
          Agent: <code>{URI.to_string(@agent_uri)}</code>
        </h1>
        <p style="font-size: 13px; color: #666;">
          <a href="/identities/agents" style="color: #0969da;">← Agents</a>
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
                <tr>
                  <td style="padding: 3px 0; color: #57606a;">auto_prompts</td>
                  <td>
                    <%= for p <- s.auto_prompts || [] do %>
                      <span style={if p.fired?, do: "color: #1f883d; margin-right: 8px;", else: "color: #57606a; margin-right: 8px;"}>
                        {p.name}: {if p.fired?, do: "fired", else: "waiting"}
                      </span>
                    <% end %>
                  </td>
                </tr>
                <tr><td style="padding: 3px 0; color: #57606a;">buffer_bytes</td><td>{s.buffer_bytes}</td></tr>
              </tbody>
            </table>

            <div style="margin-top: 12px; display: flex; gap: 8px;">
              <a
                href="/sessions"
                style="padding: 6px 14px; background: #1f883d; color: white; border: none; border-radius: 4px; cursor: pointer; font-size: 12px; text-decoration: none;"
              >📺 Open terminal (in Sessions)</a>
              <button
                type="button"
                phx-click="restart"
                id="restart-btn"
                style="padding: 6px 14px; background: white; color: #cf222e; border: 1px solid #cf222e; border-radius: 4px; cursor: pointer; font-size: 12px;"
                data-confirm="Restart PtyServer for this agent? (supervisor will respawn)"
              >Restart</button>
            </div>
          </section>

          <%!-- Phase 8b §1.10 — CC Bridges (v2) panel relocated from admin_live --%>
          <section
            id="cc-bridge-panel"
            style="margin-top: 24px; padding: 16px; border: 1px solid #d1d5da; border-radius: 6px;"
          >
            <h2 style="font-size: 14px; font-weight: 500; margin: 0 0 12px 0;">CC Bridge (v2)</h2>
            <p :if={is_nil(@bridge_entry)} style="font-size: 13px; color: #57606a;">
              No WS bridge connected for this agent. Local-pty agents only need a bridge if
              the Python sidecar is configured to mount <code>/cc_socket</code>.
            </p>
            <table :if={@bridge_entry} style="width: 100%; font-size: 13px;">
              <tbody>
                <tr>
                  <td style="padding: 3px 0; width: 200px; color: #57606a;">status</td>
                  <td style="color: #1f883d; font-weight: 600;">connected</td>
                </tr>
                <tr>
                  <td style="padding: 3px 0; color: #57606a;">connected_at</td>
                  <td style="color: #57606a;">{DateTime.to_iso8601(@bridge_entry.connected_at)}</td>
                </tr>
                <tr>
                  <td style="padding: 3px 0; color: #57606a;">client</td>
                  <td style="font-family: monospace; font-size: 11px;">{client_label(@bridge_entry)}</td>
                </tr>
              </tbody>
            </table>
          </section>

          <section :if={s.recent_output != []} style="margin-top: 24px; padding: 16px; border: 1px solid #d1d5da; border-radius: 6px; background: #1e1e1e; color: #d4d4d4;">
            <h2 style="font-size: 14px; font-weight: 500; margin: 0 0 8px 0; color: #d4d4d4;">Recent PTY output (last 50 lines)</h2>
            <pre style="font-family: 'SF Mono', Menlo, monospace; font-size: 11px; white-space: pre-wrap; margin: 0; max-height: 360px; overflow-y: auto;"><%= for line <- s.recent_output do %>{line}
<% end %></pre>
          </section>
      <% end %>
        </div>
      </:main_window>
    </IdeShell.ide_shell>
    """
  end

  # Phase 8b §1.10 — CC Bridges client_label helper. Mirrors the shape
  # the admin_live debug_panel used before relocation.
  defp client_label(%{info: %{claude_info: %{"name" => name, "version" => v}}}),
    do: "#{name} #{v}"

  defp client_label(%{info: %{claude_info: %{"name" => name}}}), do: name
  defp client_label(_), do: "—"
end
