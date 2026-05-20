defmodule EzagentPluginLiveview.AdminDashboardLive do
  @moduledoc """
  Phase 8 polish (Allen 2026-05-20) — admin dashboard at `/admin`.

  Replaces the former `/admin = Sessions` mapping (Sessions moved to
  `/sessions`). `/admin` is now reserved for sysadmin: overview KPIs
  plus links to `/admin/logs` (renamed from `/admin/observability`),
  `/admin/registry` (the KindRegistry live view, moved from
  `/admin/entities`), and `/admin/snapshots`.

  The Activity Bar's "Dashboard" item routes here.
  """
  use Phoenix.LiveView
  alias EzagentDomainUi.IdeShell
  use EzagentDomainUi.Components
  use EzagentDomainUi.Primitives

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign_overview(socket)}
  end

  defp assign_overview(socket) do
    kinds = Ezagent.KindRegistry.list_all()

    sessions =
      Enum.count(kinds, fn {uri_str, _pid} ->
        String.starts_with?(uri_str, "session://")
      end)

    workspaces =
      Enum.count(kinds, fn {uri_str, _pid} ->
        String.starts_with?(uri_str, "workspace://")
      end)

    identities =
      Enum.count(kinds, fn {uri_str, _pid} ->
        String.starts_with?(uri_str, "entity://")
      end)

    agents =
      Enum.count(kinds, fn {uri_str, _pid} ->
        String.starts_with?(uri_str, "entity://agent/")
      end)

    socket
    |> assign(:kinds_total, length(kinds))
    |> assign(:sessions, sessions)
    |> assign(:workspaces, workspaces)
    |> assign(:identities, identities)
    |> assign(:agents, agents)
  end

  @impl true
  def render(assigns) do
    assigns =
      assign_new(assigns, :current_entity_uri_str, fn ->
        URI.to_string(Map.get(assigns, :current_entity_uri) || URI.parse("entity://user/admin"))
      end)

    ~H"""
    <IdeShell.ide_shell
      current_entity_uri={@current_entity_uri_str}
      current_path="/admin"
      status={%{agents_alive: @agents, bridges: 0, debug_events: 0, version: "dev"}}
    >
      <:resource_panel>
        <div class="p-3 flex flex-col gap-px">
          <div class="text-[10px] uppercase tracking-wide text-zinc-500 mb-2">Admin</div>
          <a href="/admin" class="px-2 py-1 text-xs rounded bg-zinc-100 text-zinc-900 font-medium">Overview</a>
          <a href="/admin/logs" class="px-2 py-1 text-xs rounded text-zinc-600 hover:bg-zinc-100">Logs &amp; Audit</a>
          <a href="/admin/registry" class="px-2 py-1 text-xs rounded text-zinc-600 hover:bg-zinc-100">Registry</a>
          <a href="/admin/snapshots" class="px-2 py-1 text-xs rounded text-zinc-600 hover:bg-zinc-100">Snapshots</a>
        </div>
      </:resource_panel>
      <:main_window>
        <div class="flex-1 overflow-auto px-6 py-6 text-zinc-900">
          <.page_header title="Dashboard">
            <:subtitle>
              Sysadmin overview. Business surfaces live at the top-level
              Activity Bar links (Sessions / Workspaces / Identities / Routing /
              Plugins).
            </:subtitle>
          </.page_header>

          <div class="grid grid-cols-4 gap-3 mb-6">
            <.card>
              <.stat label="Sessions" value={@sessions} />
            </.card>
            <.card>
              <.stat label="Workspaces" value={@workspaces} />
            </.card>
            <.card>
              <.stat label="Identities" value={@identities} />
            </.card>
            <.card>
              <.stat label="Kinds alive" value={@kinds_total} />
            </.card>
          </div>

          <div class="grid grid-cols-3 gap-3">
            <a href="/admin/logs" class="block">
              <.card>
                <div class="font-medium text-sm">Logs &amp; Audit →</div>
                <div class="text-xs text-zinc-500 mt-1">
                  Dispatch audit log, events, bridges. Renamed from Observability.
                </div>
              </.card>
            </a>
            <a href="/admin/registry" class="block">
              <.card>
                <div class="font-medium text-sm">Registry →</div>
                <div class="text-xs text-zinc-500 mt-1">
                  Live <code>Ezagent.KindRegistry</code> snapshot — every Kind, every URI.
                </div>
              </.card>
            </a>
            <a href="/admin/snapshots" class="block">
              <.card>
                <div class="font-medium text-sm">Snapshots →</div>
                <div class="text-xs text-zinc-500 mt-1">
                  Persisted Kind state per <code>kind_snapshots</code> table.
                </div>
              </.card>
            </a>
          </div>
        </div>
      </:main_window>
    </IdeShell.ide_shell>
    """
  end
end
