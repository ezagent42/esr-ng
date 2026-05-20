defmodule EzagentPluginLiveview.SettingsLive do
  @moduledoc """
  Phase 8 阶段 D — Settings LV (`/admin/settings`).

  Account / Preferences / Keyboard / Access & Identity / System.
  Most sections are placeholders in Phase 8; Access & Identity
  links to existing /admin/users etc.
  """
  use Phoenix.LiveView
  alias EzagentDomainUi.IdeShell
  use EzagentDomainUi.Components
  use EzagentDomainUi.Primitives

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :section, :account)}
  end

  @impl true
  def handle_event("switch_section", %{"key" => key}, socket) do
    {:noreply, assign(socket, :section, String.to_existing_atom(key))}
  end

  @impl true
  def render(assigns) do
    assigns =
      assign_new(assigns, :current_entity_uri_str, fn ->
        URI.to_string(assigns.current_entity_uri || URI.parse("entity://user/admin"))
      end)

    ~H"""
    <IdeShell.ide_shell
      current_entity_uri={@current_entity_uri_str}
      current_path="/settings"
      status={%{agents_alive: 0, bridges: 0, debug_events: 0, version: "dev"}}
    >
      <:resource_panel>
        <div class="p-3 flex flex-col gap-px">
          <div class="text-[10px] uppercase tracking-wide text-zinc-500 mb-2">Settings</div>
          <.section_link section={@section} value={:account} label="Account" />
          <.section_link section={@section} value={:preferences} label="Preferences" />
          <.section_link section={@section} value={:keyboard} label="Keyboard" />
          <.section_link section={@section} value={:access} label="Access & Identity" />
          <.section_link section={@section} value={:system} label="System" />
        </div>
      </:resource_panel>
      <:main_window>
        <div class="flex-1 overflow-auto px-6 py-6">
          {render_section(assigns, @section)}
        </div>
      </:main_window>
    </IdeShell.ide_shell>
    """
  end

  attr :section, :atom, required: true
  attr :value, :atom, required: true
  attr :label, :string, required: true

  defp section_link(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="switch_section"
      phx-value-key={Atom.to_string(@value)}
      class={[
        "text-left px-2 py-1 text-xs rounded",
        @section == @value && "bg-zinc-100 dark:bg-zinc-900 text-zinc-900 dark:text-zinc-100 font-medium"
          || "text-zinc-600 dark:text-zinc-400 hover:bg-zinc-100 dark:hover:bg-zinc-800"
      ]}
    >
      {@label}
    </button>
    """
  end

  defp render_section(assigns, :account) do
    ~H"""
    <.page_header title="Account">
      <:subtitle>Your Entity URI and display preferences.</:subtitle>
    </.page_header>
    <.card>
      <div class="space-y-3">
        <div>
          <div class="text-xs text-zinc-500">Entity URI</div>
          <.uri_chip uri={@current_entity_uri_str} />
        </div>
        <.empty_state
          title="Account profile editing"
          description="Phase 9 will add display name + avatar customization."
        />
      </div>
    </.card>
    """
  end

  defp render_section(assigns, :preferences) do
    ~H"""
    <.page_header title="Preferences">
      <:subtitle>UI preferences.</:subtitle>
    </.page_header>
    <.empty_state
      title="Theme switcher"
      description="Phase 9 will add dark / light theme toggle. Today fixed to light."
    />
    """
  end

  defp render_section(assigns, :keyboard) do
    ~H"""
    <.page_header title="Keyboard shortcuts">
      <:subtitle>Quick reference for built-in shortcuts.</:subtitle>
    </.page_header>
    <.card>
      <div class="grid grid-cols-2 gap-2 text-xs">
        <div class="flex justify-between border-b border-zinc-100 dark:border-zinc-900 py-1">
          <span>Open Command Palette</span>
          <kbd class="font-mono text-zinc-500">⌘K / Ctrl+K</kbd>
        </div>
        <div class="flex justify-between border-b border-zinc-100 dark:border-zinc-900 py-1">
          <span>Close modal</span>
          <kbd class="font-mono text-zinc-500">Esc</kbd>
        </div>
        <div class="flex justify-between border-b border-zinc-100 dark:border-zinc-900 py-1">
          <span>Send chat message</span>
          <kbd class="font-mono text-zinc-500">Enter</kbd>
        </div>
      </div>
    </.card>
    """
  end

  defp render_section(assigns, :access) do
    ~H"""
    <.page_header title="Access & Identity">
      <:subtitle>Manage users, capabilities, API keys, Feishu bindings.</:subtitle>
    </.page_header>
    <div class="grid grid-cols-2 gap-3">
      <.access_card href="/identities/users" title="Users" desc="List + create users + set passwords" />
      <.access_card href="/admin/registry" title="Registry" desc="Live registry of every Kind instance" />
      <.access_card href="/plugins/feishu/bindings" title="Feishu bindings" desc="open_id ↔ user URI bindings" />
    </div>
    """
  end

  defp render_section(assigns, :system) do
    ~H"""
    <.page_header title="System">
      <:subtitle>Cluster + plugin metadata.</:subtitle>
    </.page_header>
    <.card>
      <div class="text-xs space-y-2">
        <div class="flex justify-between border-b border-zinc-100 dark:border-zinc-900 pb-1">
          <span>ezagent_core version</span>
          <span class="font-mono">{system_version()}</span>
        </div>
        <div class="flex justify-between border-b border-zinc-100 dark:border-zinc-900 pb-1">
          <span>Elixir / OTP</span>
          <span class="font-mono">{System.version()} / {System.otp_release()}</span>
        </div>
        <div class="flex justify-between border-b border-zinc-100 dark:border-zinc-900 pb-1">
          <span>Loaded apps</span>
          <span class="font-mono">{loaded_app_count()}</span>
        </div>
      </div>
    </.card>
    """
  end

  attr :href, :string, required: true
  attr :title, :string, required: true
  attr :desc, :string, required: true

  defp access_card(assigns) do
    ~H"""
    <a href={@href} class="block">
      <.card>
        <div class="font-medium text-sm">{@title}</div>
        <div class="text-xs text-zinc-500 mt-1">{@desc}</div>
      </.card>
    </a>
    """
  end

  defp system_version do
    case Application.spec(:ezagent_core, :vsn) do
      nil -> "dev"
      vsn -> to_string(vsn)
    end
  end

  defp loaded_app_count do
    Application.loaded_applications() |> length()
  end
end
