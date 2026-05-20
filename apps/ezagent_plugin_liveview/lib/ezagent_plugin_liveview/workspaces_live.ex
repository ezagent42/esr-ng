defmodule EzagentPluginLiveview.WorkspacesLive do
  @moduledoc """
  /workspaces — list every persisted Workspace + form to create.

  Reads `Ezagent.Workspace.list_persisted/0` (which hits SQLite via
  `Ezagent.Workspace.Store`) — the persisted set, not the live-Kind set.
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
  alias EzagentDomainUi.IdeShell
  use EzagentDomainUi.Components
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
    Ezagent.Workspace.list_persisted()
    |> Enum.map(fn ws ->
      live_pid =
        case Ezagent.KindRegistry.lookup(ws.uri) do
          {:ok, pid} -> pid
          :error -> nil
        end

      Map.put(ws, :live_pid, live_pid)
    end)
  end

  @impl true
  def handle_event("create_workspace", %{"new_workspace" => %{"name" => name}}, socket)
      when is_binary(name) and name != "" do
    case Ezagent.Workspace.create(String.trim(name), %{}) do
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
    # Phase 8 阶段 C: wrap in IdeShell; old standalone page_header replaced
    # by IDE Shell's top command bar + activity bar.
    assigns =
      assign_new(assigns, :current_entity_uri_str, fn ->
        URI.to_string(assigns.current_entity_uri || URI.parse("entity://user/admin"))
      end)

    ~H"""
    <IdeShell.ide_shell
      current_entity_uri={@current_entity_uri_str}
      current_path="/workspaces"
      status={%{agents_alive: 0, bridges: 0, debug_events: 0, version: "dev"}}
      is_admin?={@is_admin?}
    >
      <:resource_panel>
        <div class="p-3">
          <div class="text-[10px] uppercase tracking-wide text-zinc-500 mb-2">Workspaces</div>
          <a
            :for={ws <- @workspaces}
            href={"/workspaces/#{ws.name}"}
            class="block px-2 py-1 text-xs hover:bg-zinc-100 dark:hover:bg-zinc-800 rounded font-mono text-zinc-700 dark:text-zinc-300"
          >
            {ws.name}
          </a>
        </div>
      </:resource_panel>
      <:main_window>
        <div class="flex-1 overflow-auto px-6 py-6 text-zinc-900 dark:text-zinc-100">
        <.page_header title="Workspaces">
        <:subtitle>
          Persisted cluster configurations — members + session templates + routing rules.
        </:subtitle>
      </.page_header>

      <.card id="create-workspace" class="mb-6">
        <:header>+ New Workspace</:header>
        <.form for={@new_form} phx-submit="create_workspace" class="flex gap-2 items-center">
          <input
            type="text"
            name="new_workspace[name]"
            id="new_workspace_name"
            placeholder="architect-review"
            class="flex-1 px-3 py-1.5 text-sm border border-zinc-300 dark:border-zinc-700 rounded-md focus:outline-none focus:ring-2 focus:ring-zinc-500"
          />
          <.button type="submit" variant="primary" size="sm">Create</.button>
        </.form>
        <p :if={@flash_error} class="text-red-700 dark:text-red-300 text-xs mt-2">{@flash_error}</p>
      </.card>

      <section id="workspaces-list">
        <p :if={@workspaces == []} id="empty" class="text-zinc-500 italic text-sm">
          No workspaces yet. Use the form above to create the first one.
        </p>

        <.card :if={@workspaces != []} class="p-0">
          <table id="workspaces-table" class="w-full text-sm">
            <thead class="bg-zinc-50 dark:bg-zinc-950 border-b border-zinc-200 dark:border-zinc-800">
              <tr class="text-left text-xs uppercase tracking-wide text-zinc-500">
                <th class="px-4 py-2">Name</th>
                <th class="py-2">URI</th>
                <th class="py-2">Members</th>
                <th class="py-2">Templates</th>
                <th class="py-2">Rules</th>
                <th class="py-2">Live</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={ws <- @workspaces} class="border-b border-zinc-100 dark:border-zinc-900 last:border-0">
                <td class="px-4 py-2 font-medium">{ws.name}</td>
                <td class="py-2 font-mono text-xs text-zinc-500">{URI.to_string(ws.uri)}</td>
                <td class="py-2 tabular-nums">{length(ws.members)}</td>
                <td class="py-2 tabular-nums">{map_size(ws.session_templates)}</td>
                <td class="py-2 tabular-nums">{length(ws.routing_rules)}</td>
                <td class="py-2">
                  <.badge :if={ws.live_pid} variant="success">live</.badge>
                  <.badge :if={!ws.live_pid} variant="danger">down</.badge>
                </td>
                <td class="py-2 pr-4 text-right">
                  <a
                    href={"/workspaces/#{ws.name}"}
                    class="text-zinc-600 dark:text-zinc-400 hover:text-zinc-900 dark:hover:text-zinc-100 text-xs"
                  >detail →</a>
                </td>
              </tr>
            </tbody>
          </table>
        </.card>
      </section>
        </div>
      </:main_window>
    </IdeShell.ide_shell>
    """
  end
end
