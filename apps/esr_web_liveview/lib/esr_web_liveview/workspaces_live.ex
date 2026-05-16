defmodule EsrWebLiveview.WorkspacesLive do
  @moduledoc """
  /admin/workspaces — list every persisted Workspace + form to create.

  Reads `Esr.Workspace.list_persisted/0` (which hits SQLite via
  `Esr.Workspace.Store`) — the persisted set, not the live-Kind set.
  Phase 4d separates "what's declared to exist" (Store) from "what's
  currently spawned" (KindRegistry); a healthy system has them equal,
  but during transient errors the Store row exists even when the live
  Kind crashed.

  ## Why a separate LV (not a tab inside admin_live)

  Per Phase 4d split — Workspace UI is a different surface (admin_live
  is per-session chat; workspaces_live is cluster-shape config). Each
  is on its own URL, no shared assigns. They navigate via plain links.
  """

  use Phoenix.LiveView
  import Phoenix.Component

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:workspaces, list_workspaces())
     |> assign(:flash_error, nil)
     |> assign(:new_form, to_form(%{"name" => ""}, as: "new_workspace"))}
  end

  defp list_workspaces do
    Esr.Workspace.list_persisted()
    |> Enum.map(fn ws ->
      live_pid =
        case Esr.KindRegistry.lookup(ws.uri) do
          {:ok, pid} -> pid
          :error -> nil
        end

      Map.put(ws, :live_pid, live_pid)
    end)
  end

  @impl true
  def handle_event("create_workspace", %{"new_workspace" => %{"name" => name}}, socket)
      when is_binary(name) and name != "" do
    case Esr.Workspace.create(String.trim(name), %{}) do
      {:ok, _pid} ->
        {:noreply,
         socket
         |> assign(:workspaces, list_workspaces())
         |> assign(:new_form, to_form(%{"name" => ""}, as: "new_workspace"))
         |> assign(:flash_error, nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :flash_error, "create failed: #{inspect(reason)}")}
    end
  end

  def handle_event("create_workspace", _params, socket) do
    {:noreply, assign(socket, :flash_error, "Workspace name is required.")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div style="max-width: 1000px; margin: 0 auto; padding: 24px; font-family: -apple-system, sans-serif;">
      <header>
        <h1 style="font-size: 22px; font-weight: 600;">Workspaces</h1>
        <p style="font-size: 13px; color: #666;">
          Persisted cluster configurations — members + session templates + routing rules.
          <a href="/admin" style="color: #0969da;">← back to /admin</a>
        </p>
      </header>

      <section id="create-workspace" style="margin-top: 24px; padding: 16px; border: 1px solid #d1d5da; border-radius: 6px;">
        <h2 style="font-size: 14px; font-weight: 500; margin: 0 0 8px 0;">+ New Workspace</h2>
        <.form for={@new_form} phx-submit="create_workspace" style="display: flex; gap: 8px;">
          <input
            type="text"
            name="new_workspace[name]"
            id="new_workspace_name"
            placeholder="architect-review"
            style="flex: 1; padding: 6px 10px; border: 1px solid #d1d5da; border-radius: 4px;"
          />
          <button
            type="submit"
            style="padding: 6px 16px; background: #1f883d; color: white; border: none; border-radius: 4px; cursor: pointer;"
          >
            Create
          </button>
        </.form>
        <p :if={@flash_error} style="color: #cf222e; font-size: 13px; margin-top: 8px;">{@flash_error}</p>
      </section>

      <section id="workspaces-list" style="margin-top: 24px;">
        <p :if={@workspaces == []} id="empty" style="color: #57606a; font-style: italic;">
          No workspaces yet. Use the form above to create the first one.
        </p>

        <table :if={@workspaces != []} id="workspaces-table" style="width: 100%; font-size: 14px; border-collapse: collapse;">
          <thead>
            <tr style="border-bottom: 2px solid #d1d5da;">
              <th style="text-align: left; padding: 8px 4px;">Name</th>
              <th style="text-align: left;">URI</th>
              <th style="text-align: left;">Members</th>
              <th style="text-align: left;">Templates</th>
              <th style="text-align: left;">Rules</th>
              <th style="text-align: left;">Live?</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={ws <- @workspaces} style="border-bottom: 1px solid #eaeef2;">
              <td style="padding: 6px 4px; font-weight: 500;">{ws.name}</td>
              <td style="font-family: monospace; font-size: 12px; color: #57606a;">{URI.to_string(ws.uri)}</td>
              <td>{length(ws.members)}</td>
              <td>{map_size(ws.session_templates)}</td>
              <td>{length(ws.routing_rules)}</td>
              <td>
                <span :if={ws.live_pid} style="color: #1f883d;">●</span>
                <span :if={!ws.live_pid} style="color: #cf222e;">○</span>
              </td>
              <td>
                <a
                  href={"/admin/workspaces/#{ws.name}"}
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
end
