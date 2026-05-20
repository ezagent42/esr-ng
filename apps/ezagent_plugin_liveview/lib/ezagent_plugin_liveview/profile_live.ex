defmodule EzagentPluginLiveview.ProfileLive do
  @moduledoc """
  Phase 8 polish (Allen 2026-05-20) — `/profile` for the current entity.

  Reached from the IDE Shell avatar dropdown. Shows the current entity's
  URI, caps count, API key count, and quick links to detail pages.
  """
  use Phoenix.LiveView
  alias EzagentDomainUi.IdeShell
  use EzagentDomainUi.Components
  use EzagentDomainUi.Primitives

  @impl true
  def mount(_params, _session, socket) do
    entity_uri = socket.assigns.current_entity_uri || URI.parse("entity://user/admin")
    entity_uri_str = URI.to_string(entity_uri)

    {:ok,
     socket
     |> assign(:entity_uri_str, entity_uri_str)
     |> assign(:caps_count, count_caps(entity_uri))
     |> assign(:api_keys_count, count_api_keys(entity_uri))}
  end

  defp count_caps(uri) do
    try do
      uri |> Ezagent.Identity.list_caps_for() |> MapSet.size()
    catch
      _, _ -> 0
    end
  end

  defp count_api_keys(_uri) do
    # Best-effort; ApiKeys API hasn't been finalized for read-only count.
    # TODO Phase 9 — wire through Ezagent.ApiKeys.list_for/1.
    0
  end

  @impl true
  def render(assigns) do
    assigns = assign_new(assigns, :current_entity_uri_str, fn -> assigns.entity_uri_str end)

    ~H"""
    <IdeShell.ide_shell
      current_entity_uri={@current_entity_uri_str}
      current_path="/profile"
      status={%{agents_alive: 0, bridges: 0, debug_events: 0, version: "dev"}}
      is_admin?={@is_admin?}
    >
      <:main_window>
        <div class="flex-1 overflow-auto px-6 py-6 max-w-3xl">
          <.page_header title="Profile">
            <:subtitle>Your entity URI and access summary.</:subtitle>
          </.page_header>

          <.card class="mt-4">
            <div class="flex items-center gap-4">
              <.avatar uri={@entity_uri_str} size="md" />
              <div>
                <div class="text-xs text-zinc-500">Entity URI</div>
                <.uri_chip uri={@entity_uri_str} />
              </div>
            </div>
          </.card>

          <div class="grid grid-cols-2 gap-3 mt-4">
            <a href={"/identities/users/" <> URI.encode_www_form(@entity_uri_str) <> "/caps"} class="block">
              <.card>
                <div class="font-medium text-sm">Capabilities</div>
                <div class="text-2xl font-mono mt-1">{@caps_count}</div>
                <div class="text-xs text-zinc-500 mt-1">→ Manage</div>
              </.card>
            </a>
            <a href={"/identities/users/" <> URI.encode_www_form(@entity_uri_str) <> "/api-keys"} class="block">
              <.card>
                <div class="font-medium text-sm">API Keys</div>
                <div class="text-2xl font-mono mt-1">{@api_keys_count}</div>
                <div class="text-xs text-zinc-500 mt-1">→ Manage</div>
              </.card>
            </a>
          </div>

          <div class="mt-6 text-right">
            <form action="/logout" method="post">
              <.button variant="ghost" type="submit">Sign out</.button>
            </form>
          </div>
        </div>
      </:main_window>
    </IdeShell.ide_shell>
    """
  end
end
