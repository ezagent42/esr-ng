defmodule EzagentPluginLiveview.Admin.DebugPanel do
  @moduledoc """
  Below-the-fold: CC Bridges table + collapsible Debug area
  (Echo button + Manual Dispatch form + Audit Log stream).

  Stateless — parent (AdminLive) owns the :invocations stream, manual
  dispatch form, and all event handlers (echo_test / manual_dispatch).
  """

  use Phoenix.Component

  attr :connected_bridges, :list, required: true
  attr :form, :map, required: true
  attr :invocations_stream, :any, required: true
  attr :cc_events, :list, default: []

  def debug_panel(assigns) do
    ~H"""
    <section :if={@cc_events != []} id="cc-events-panel" style="margin-top: 24px;">
      <h2 style="font-size: 16px; font-weight: 500; margin: 0 0 8px 0;">
        CC Events (hook-reported, last 20)
      </h2>
      <p style="font-size: 12px; color: #57606a; margin: 0 0 8px 0;">
        Errors reported directly by CC hooks via <code>POST /api/cc-events</code> —
        bypasses the agent's dispatch path so failures survive when the agent itself is down.
      </p>
      <table id="cc-events-table" style="width: 100%; font-size: 13px; border-collapse: collapse;">
        <thead>
          <tr style="border-bottom: 1px solid #d1d5da;">
            <th style="text-align: left; padding: 6px 0;">level</th>
            <th style="text-align: left;">bridge_id</th>
            <th style="text-align: left;">type</th>
            <th style="text-align: left;">text</th>
            <th style="text-align: left;">at</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={ev <- @cc_events} style={cc_event_row_style(ev.level)}>
            <td style="padding: 4px 6px; font-weight: 600;">{ev.level}</td>
            <td style="font-family: monospace; font-size: 11px;">{ev.bridge_id}</td>
            <td style="font-family: monospace; font-size: 11px;">{ev.type}</td>
            <td>{ev.text}</td>
            <td style="color: #666; font-size: 11px;">{DateTime.to_iso8601(ev.at)}</td>
          </tr>
        </tbody>
      </table>
    </section>

    <section id="cc-bridges" style="margin-top: 24px;">
      <h2 style="font-size: 16px; font-weight: 500; margin: 0 0 8px 0;">CC Bridges (v2)</h2>
      <p :if={@connected_bridges == []} id="bridge-empty" style="font-size: 13px; color: #57606a;">
        No connected bridges. A bridge connects when a cc.pty Template instance spawns a claude process whose Python sidecar joins <code>/cc_socket</code>.
      </p>
      <table :if={@connected_bridges != []} id="bridges-table" style="width: 100%; font-size: 13px; border-collapse: collapse;">
        <thead>
          <tr style="border-bottom: 1px solid #d1d5da;">
            <th style="text-align: left; padding: 4px 0;">agent_uri</th>
            <th style="text-align: left;">status</th>
            <th style="text-align: left;">connected_at</th>
            <th style="text-align: left;">client</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={{agent_uri, entry} <- @connected_bridges} style="border-bottom: 1px solid #eee;">
            <td style="font-family: monospace; padding: 4px 0;">{URI.to_string(agent_uri)}</td>
            <td style="color: #1f883d; font-weight: 600;">connected</td>
            <td style="color: #57606a;">{DateTime.to_iso8601(entry.connected_at)}</td>
            <td style="font-family: monospace; font-size: 11px;">{client_label(entry)}</td>
          </tr>
        </tbody>
      </table>
    </section>

    <section id="debug-area" style="margin-top: 32px;">
      <details>
        <summary style="font-size: 14px; font-weight: 500; cursor: pointer; padding: 8px 0;">
          Debug (Echo / Manual Dispatch / Audit Log)
        </summary>

        <div id="quick-actions" style="margin-top: 16px;">
          <h3 style="font-size: 14px; font-weight: 500; margin: 0 0 8px 0;">Quick Actions</h3>
          <button
            type="button"
            phx-click="echo_test"
            id="echo-test-btn"
            style="padding: 8px 16px; background: #0969da; color: white; border: none; border-radius: 4px; cursor: pointer;"
          >
            Echo 测试
          </button>
        </div>

        <div id="manual-dispatch" style="margin-top: 16px;">
          <h3 style="font-size: 14px; font-weight: 500; margin: 0 0 8px 0;">Manual Dispatch</h3>
          <.form for={@form} phx-submit="manual_dispatch">
            <div style="margin-bottom: 8px;">
              <label style="display: block; font-size: 13px; font-weight: 500;" for="manual_dispatch_target">target</label>
              <input
                type="text"
                name="manual_dispatch[target]"
                id="manual_dispatch_target"
                placeholder="agent://echo/default/behavior/echo/say"
                style="width: 100%; padding: 6px 10px; border: 1px solid #d1d5da; border-radius: 4px;"
              />
            </div>
            <div style="margin-bottom: 8px;">
              <label style="display: block; font-size: 13px; font-weight: 500;" for="manual_dispatch_args">args (JSON)</label>
              <input
                type="text"
                name="manual_dispatch[args]"
                id="manual_dispatch_args"
                placeholder='{"msg": "hello"}'
                style="width: 100%; padding: 6px 10px; border: 1px solid #d1d5da; border-radius: 4px;"
              />
            </div>
            <div style="margin-bottom: 8px;">
              <label style="display: block; font-size: 13px; font-weight: 500;" for="manual_dispatch_mode">mode</label>
              <select
                name="manual_dispatch[mode]"
                id="manual_dispatch_mode"
                style="padding: 6px 10px; border: 1px solid #d1d5da; border-radius: 4px;"
              >
                <option value="call">call</option>
                <option value="cast">cast</option>
              </select>
            </div>
            <button
              type="submit"
              style="padding: 8px 16px; background: white; color: #0969da; border: 1px solid #0969da; border-radius: 4px; cursor: pointer;"
            >
              Dispatch
            </button>
          </.form>
        </div>

        <div id="audit-stream" style="margin-top: 16px;">
          <h3 style="font-size: 14px; font-weight: 500; margin: 0 0 8px 0;">Audit Log (last 50)</h3>
          <table style="width: 100%; font-size: 13px; border-collapse: collapse;">
            <thead>
              <tr style="border-bottom: 1px solid #d1d5da;">
                <th style="text-align: left; padding: 6px 0;">target</th>
                <th style="text-align: left;">action</th>
                <th style="text-align: left;">authz</th>
                <th style="text-align: left;">result</th>
                <th style="text-align: left;">duration_us</th>
                <th style="text-align: left;">at</th>
              </tr>
            </thead>
            <tbody id="invocations" phx-update="stream">
              <tr :for={{dom_id, row} <- @invocations_stream} id={dom_id} style="border-bottom: 1px solid #eee;">
                <td style="padding: 4px 0; font-family: monospace; font-size: 11px;">{row.target}</td>
                <td>{row.action}</td>
                <td>{row.authz}</td>
                <td style="font-family: monospace; font-size: 11px;">{row.result}</td>
                <td>{row.duration_us}</td>
                <td style="color: #666;">{row.at}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </details>
    </section>
    """
  end

  defp client_label(%{info: %{claude_info: %{"name" => name, "version" => v}}}),
    do: "#{name} #{v}"

  defp client_label(%{info: %{claude_info: %{"name" => name}}}), do: name
  defp client_label(_), do: "—"

  defp cc_event_row_style("error"),
    do: "border-bottom: 1px solid #eee; background: #ffebe9;"

  defp cc_event_row_style("warning"),
    do: "border-bottom: 1px solid #eee; background: #fff8c5;"

  defp cc_event_row_style(_),
    do: "border-bottom: 1px solid #eee; background: #ddf4ff;"
end
