defmodule EzagentPluginLiveview.AutoDeriveLive do
  @moduledoc """
  Phase 6 PR 10 — generic LV that lists / details any Kind via
  `EsrDomainUi.AutoDerive`.

  Two modes (drive by URL):
    /admin/auto/:kind          → list view (table of live URIs +
                                 slice keys + behaviors)
    /admin/auto/:kind/:uri     → detail view (URI-decoded; slices
                                 rendered as <pre>{inspect})

  Validates the auto-derive thesis: ANY Kind, including 3rd-party
  plugin Kinds nobody on the core team knows about, gets a working
  admin surface for free.
  """

  use Phoenix.LiveView
  use EsrDomainUi.Components
  import Phoenix.Component

  alias EsrDomainUi.AutoDerive

  @impl true
  def mount(params, _session, socket) do
    kind = String.to_atom(params["kind"])

    {:ok,
     socket
     |> assign(:kind, kind)
     |> assign(:detail_uri, decode_uri(params["uri"]))
     |> assign(:instances, AutoDerive.list_instances(kind))
     |> maybe_load_detail()}
  end

  @impl true
  def handle_params(params, _url, socket) do
    new_kind = String.to_atom(params["kind"])

    {:noreply,
     socket
     |> assign(:kind, new_kind)
     |> assign(:detail_uri, decode_uri(params["uri"]))
     |> assign(:instances, AutoDerive.list_instances(new_kind))
     |> maybe_load_detail()}
  end

  defp decode_uri(nil), do: nil

  defp decode_uri(encoded) do
    case URI.new(URI.decode(encoded)) do
      {:ok, uri} -> uri
      _ -> nil
    end
  end

  defp maybe_load_detail(%{assigns: %{detail_uri: nil}} = socket) do
    assign(socket, :detail, nil)
  end

  defp maybe_load_detail(%{assigns: %{detail_uri: uri}} = socket) do
    case AutoDerive.instance_detail(uri) do
      {:ok, detail} -> assign(socket, :detail, detail)
      {:error, reason} -> assign(socket, :detail, {:error, reason})
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-6xl mx-auto px-6 py-8 font-sans text-zinc-900">
      <.page_header title={"Auto-derived: " <> Atom.to_string(@kind)}>
        <:subtitle>
          Generic admin surface, no hand-written code per Kind.
          <a href="/admin" class="text-zinc-600 underline hover:text-zinc-900 ml-1">← /admin</a>
        </:subtitle>
      </.page_header>

      <div :if={!@detail_uri}>
        <.card>
          <:header>{length(@instances)} live instance(s)</:header>
          <p :if={@instances == []} class="text-zinc-500 italic text-sm">
            No live instances of <code>{@kind}</code>.
          </p>

          <table :if={@instances != []} class="w-full text-sm">
            <thead class="bg-zinc-50 border-b border-zinc-200">
              <tr class="text-left text-xs uppercase tracking-wide text-zinc-500">
                <th class="px-2 py-2">URI</th>
                <th class="py-2">Slice keys</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={inst <- @instances} class="border-b border-zinc-100 last:border-0">
                <td class="px-2 py-2 font-mono text-xs">{URI.to_string(inst.uri)}</td>
                <td class="py-2">
                  <.badge :for={k <- inst.slice_keys} variant="info" class="mr-1">
                    {k}
                  </.badge>
                </td>
                <td class="py-2 text-right pr-2">
                  <a
                    href={"/admin/auto/" <> Atom.to_string(@kind) <> "/" <> URI.encode_www_form(URI.to_string(inst.uri))}
                    class="text-zinc-600 hover:text-zinc-900 text-xs"
                  >detail →</a>
                </td>
              </tr>
            </tbody>
          </table>
        </.card>
      </div>

      <div :if={@detail_uri}>
        <.card class="mb-4">
          <:header>{URI.to_string(@detail_uri)}</:header>
          <%= case @detail do %>
            <% nil -> %>
              <p class="text-zinc-500 italic text-sm">Loading…</p>
            <% {:error, reason} -> %>
              <p class="text-red-700 text-sm">Error: {inspect(reason)}</p>
            <% detail when is_map(detail) -> %>
              <div class="space-y-2">
                <div>
                  <span class="text-xs uppercase text-zinc-500">Kind module</span>
                  <code class="block text-xs">{detail.kind_module}</code>
                </div>
                <div>
                  <span class="text-xs uppercase text-zinc-500">Behaviors</span>
                  <ul class="text-xs">
                    <li :for={b <- detail.behaviors}>
                      <code>{b.module}</code> — {Enum.join(b.actions, ", ")}
                    </li>
                  </ul>
                </div>
              </div>
          <% end %>
        </.card>

        <.card :if={is_map(@detail)}>
          <:header>Slices</:header>
          <%= for {slice_key, slice_val} <- (@detail && @detail[:slices]) || %{} do %>
            <div class="mb-3">
              <div class="text-xs uppercase text-zinc-500 mb-1">{slice_key}</div>
              <pre class="text-xs bg-zinc-50 border border-zinc-200 rounded p-2 overflow-x-auto"><%= inspect(slice_val, pretty: true) %></pre>
            </div>
          <% end %>
        </.card>

        <p class="mt-4">
          <a
            href={"/admin/auto/" <> Atom.to_string(@kind)}
            class="text-zinc-600 hover:text-zinc-900 text-xs"
          >← back to list</a>
        </p>
      </div>
    </div>
    """
  end
end
