defmodule EzagentPluginLiveview.IdentitiesLive do
  @moduledoc """
  Phase 8 polish (Allen 2026-05-20) — Identities "address book" at
  `/identities`.

  Per Allen's deliberation: Users + Agents are entity sub-types so
  they belong under the same Identities surface. This LV reads
  `Ezagent.KindRegistry.list_all/0` filtered to `entity://*`, groups
  by sub-type (user / agent flavor), and renders entity cards with
  avatar + URI + StatusDot + action links.

  Distinct from `/admin/registry` (the raw KindRegistry sysadmin view)
  — Identities is the user-facing directory.
  """
  use Phoenix.LiveView
  alias EzagentDomainUi.IdeShell
  use EzagentDomainUi.Components
  use EzagentDomainUi.Primitives

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     socket
     |> assign(:filter, params["filter"] || "all")
     |> assign_entities()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:filter, params["filter"] || "all")
     |> assign_entities()}
  end

  defp assign_entities(socket) do
    rows =
      Ezagent.KindRegistry.list_all()
      |> Enum.flat_map(fn {uri_str, pid} ->
        case URI.new(uri_str) do
          {:ok, %URI{scheme: "entity", host: host, path: "/" <> name} = uri}
          when host in ["user", "agent"] ->
            [
              %{
                uri: uri,
                uri_str: uri_str,
                host: host,
                name: name,
                flavor: flavor_for(host, name),
                pid: pid,
                alive: is_pid(pid) and Process.alive?(pid)
              }
            ]

          _ ->
            []
        end
      end)
      |> Enum.filter(&matches_filter?(&1, socket.assigns.filter))
      |> Enum.sort_by(& &1.uri_str)

    flavors =
      rows
      |> Enum.filter(&(&1.host == "agent"))
      |> Enum.map(& &1.flavor)
      |> Enum.uniq()
      |> Enum.sort()

    socket
    |> assign(:entities, rows)
    |> assign(:agent_flavors, flavors)
  end

  # "cc_demo-builder" → "cc"; "echo_default" → "echo"; no underscore → ""
  defp flavor_for("agent", name) do
    case String.split(name, "_", parts: 2) do
      [flavor, _] -> flavor
      _ -> ""
    end
  end

  defp flavor_for(_, _), do: ""

  defp matches_filter?(_, "all"), do: true
  defp matches_filter?(%{host: "user"}, "users"), do: true
  defp matches_filter?(%{host: "agent"}, "agents"), do: true
  defp matches_filter?(%{host: "agent", flavor: flavor}, "agent:" <> flavor), do: true
  defp matches_filter?(_, _), do: false

  @impl true
  def render(assigns) do
    assigns =
      assign_new(assigns, :current_entity_uri_str, fn ->
        URI.to_string(Map.get(assigns, :current_entity_uri) || URI.parse("entity://user/admin"))
      end)

    ~H"""
    <IdeShell.ide_shell
      current_entity_uri={@current_entity_uri_str}
      current_path="/identities"
      status={%{agents_alive: 0, bridges: 0, debug_events: 0, version: "dev"}}
    >
      <:resource_panel>
        <div class="p-3 flex flex-col gap-1">
          <div class="text-[10px] uppercase tracking-wide text-zinc-500 mb-1">Filters</div>
          <.filter_chip filter={@filter} value="all" label="All" />
          <.filter_chip filter={@filter} value="users" label="Users" />
          <.filter_chip filter={@filter} value="agents" label="Agents" />
          <div :if={@agent_flavors != []} class="text-[10px] uppercase tracking-wide text-zinc-500 mt-3 mb-1">By flavor</div>
          <.filter_chip
            :for={f <- @agent_flavors}
            filter={@filter}
            value={"agent:" <> f}
            label={"agent: " <> f}
          />
          <div class="text-[10px] uppercase tracking-wide text-zinc-500 mt-3 mb-1">Manage</div>
          <a href="/identities/users" class="px-2 py-1 text-xs rounded text-zinc-600 hover:bg-zinc-100">+ Users admin</a>
        </div>
      </:resource_panel>
      <:main_window>
        <div class="flex-1 overflow-auto px-6 py-6 text-zinc-900">
          <.page_header title="Identities">
            <:subtitle>
              The directory of every live entity — users and agents.
              Driven by <code>Ezagent.KindRegistry</code> filtered to
              <code>entity://*</code>.
            </:subtitle>
          </.page_header>

          <p :if={@entities == []} id="identities-empty" class="text-sm text-zinc-500 italic">
            No entities match the current filter.
          </p>

          <div :if={@entities != []} class="grid grid-cols-1 md:grid-cols-2 gap-3">
            <.identity_card :for={e <- @entities} entity={e} />
          </div>
        </div>
      </:main_window>
    </IdeShell.ide_shell>
    """
  end

  attr :filter, :string, required: true
  attr :value, :string, required: true
  attr :label, :string, required: true

  defp filter_chip(assigns) do
    ~H"""
    <a
      href={"/identities?filter=" <> URI.encode_www_form(@value)}
      class={[
        "px-2 py-1 text-xs rounded font-mono",
        @filter == @value && "bg-zinc-900 text-white" || "text-zinc-600 hover:bg-zinc-100"
      ]}
    >{@label}</a>
    """
  end

  attr :entity, :map, required: true

  defp identity_card(assigns) do
    ~H"""
    <.card>
      <div class="flex items-start gap-3">
        <.avatar uri={@entity.uri_str} size="md" />
        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-2">
            <span class="font-mono text-xs truncate">{@entity.uri_str}</span>
            <.status_dot color={(@entity.alive && "green") || "gray"} />
          </div>
          <div class="text-[11px] text-zinc-500 mt-1">
            {@entity.host == "user" && "User" || ("Agent (" <> @entity.flavor <> ")")}
          </div>
          <div class="flex gap-3 mt-2 text-xs">
            <%= if @entity.host == "user" do %>
              <a
                href={"/identities/users/" <> URI.encode_www_form(@entity.uri_str) <> "/caps"}
                class="text-zinc-700 hover:text-zinc-900 underline"
              >Caps</a>
              <a
                href={"/identities/users/" <> URI.encode_www_form(@entity.uri_str) <> "/api-keys"}
                class="text-zinc-700 hover:text-zinc-900 underline"
              >API Keys</a>
            <% else %>
              <a
                href={"/identities/agents/" <> URI.encode_www_form(@entity.uri_str)}
                class="text-zinc-700 hover:text-zinc-900 underline"
              >Status</a>
            <% end %>
          </div>
        </div>
      </div>
    </.card>
    """
  end
end
