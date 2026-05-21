defmodule EzagentPluginLiveview.FeishuBindingsLive do
  @moduledoc """
  Phase 6 PR 15 — /plugins/feishu/bindings.

  Lists all `feishu_user_bindings` rows + a bind form. The unbind
  button on each row deletes via `EzagentPluginFeishu.UserBinding.unbind/1`.

  The bind form goes through `BindingPolicy.apply/2` so the cap-grant
  side effect fires the same way `mix ezagent.feishu.bind` does.
  """

  use Phoenix.LiveView
  alias EzagentDomainUi.IdeShell
  use EzagentDomainUi.Components
  import Phoenix.Component

  alias EzagentPluginFeishu.{BindingPolicy, UserBinding}

  @impl true
  def mount(_params, session, socket) do
    admin_uri =
      case Map.get(session || %{}, "current_entity_uri") do
        nil -> "entity://user/system/admin"
        s -> s
      end

    {:ok,
     socket
     |> assign(:admin_uri, admin_uri)
     |> assign(:bindings, UserBinding.list_all())
     |> assign(:flash_info, nil)
     |> assign(:flash_error, nil)
     |> assign(:bind_form, to_form(%{"open_id" => "", "user_uri" => "entity://user/"}, as: "bind"))}
  end

  @impl true
  def handle_event("bind", %{"bind" => %{"open_id" => open_id, "user_uri" => user_uri}}, socket) do
    open_id = String.trim(open_id)
    user_uri = String.trim(user_uri)

    cond do
      open_id == "" or user_uri == "" or user_uri == "entity://user/" ->
        {:noreply, assign(socket, :flash_error, "open_id and user_uri are required")}

      true ->
        case UserBinding.bind(open_id, user_uri, socket.assigns.admin_uri) do
          {:ok, _} ->
            _ = BindingPolicy.apply(user_uri, socket.assigns.admin_uri)

            {:noreply,
             socket
             |> assign(:bindings, UserBinding.list_all())
             |> assign(:flash_info, "Bound #{open_id} → #{user_uri}")
             |> assign(:flash_error, nil)
             |> assign(:bind_form, to_form(%{"open_id" => "", "user_uri" => "entity://user/"}, as: "bind"))}

          {:error, reason} ->
            {:noreply, assign(socket, :flash_error, "bind failed: #{inspect(reason)}")}
        end
    end
  end

  def handle_event("unbind", %{"open-id" => open_id}, socket) do
    case UserBinding.unbind(open_id) do
      :ok ->
        {:noreply,
         socket
         |> assign(:bindings, UserBinding.list_all())
         |> assign(:flash_info, "Unbound #{open_id}")
         |> assign(:flash_error, nil)}

      {:error, :not_found} ->
        {:noreply, assign(socket, :flash_error, "no binding for #{open_id}")}
    end
  end

  @impl true
  def render(assigns) do
    assigns =
      assign_new(assigns, :current_entity_uri_str, fn ->
        URI.to_string(Map.get(assigns, :current_entity_uri) || URI.parse("entity://user/system/admin"))
      end)

    ~H"""
    <IdeShell.ide_shell
      current_entity_uri={@current_entity_uri_str}
      current_path="/plugins/feishu/bindings"
      status={%{agents_alive: 0, bridges: 0, debug_events: 0, version: "dev"}}
      is_admin?={@is_admin?}
      is_system_member?={@is_system_member?}
      workspaces={@workspaces}
    >
      <:main_window>
        <div class="flex-1 overflow-auto px-6 py-6 text-zinc-900 dark:text-zinc-100">
      <.page_header title="Feishu user bindings">
        <:subtitle>
          Map a Feishu open_id to a local ESR user URI. The bound user
          gets the default session-participation caps via BindingPolicy.
          (chat_id ↔ session bindings live in a separate table — manage
          them with `mix ezagent.feishu.chat.bind`.)
          <a href="/plugins" class="text-zinc-600 dark:text-zinc-400 underline hover:text-zinc-900 dark:hover:text-zinc-100 ml-1">← Plugins</a>
        </:subtitle>
      </.page_header>

      <p :if={@flash_info} class="text-emerald-700 dark:text-emerald-300 text-sm mb-3">{@flash_info}</p>
      <p :if={@flash_error} class="text-red-700 dark:text-red-300 text-sm mb-3">{@flash_error}</p>

      <.card class="mb-6">
        <:header>Bind</:header>
        <.form for={@bind_form} phx-submit="bind" class="grid grid-cols-2 gap-2 items-end">
          <label class="text-xs">
            Feishu open_id
            <input
              type="text"
              name="bind[open_id]"
              placeholder="ou_6b11faf8e9..."
              class="block w-full px-2 py-1 text-sm border border-zinc-300 dark:border-zinc-700 rounded-md font-mono"
            />
          </label>
          <label class="text-xs">
            local user URI
            <input
              type="text"
              name="bind[user_uri]"
              value="entity://user/"
              class="block w-full px-2 py-1 text-sm border border-zinc-300 dark:border-zinc-700 rounded-md font-mono"
            />
          </label>
          <div class="col-span-2 flex justify-end">
            <.button type="submit" variant="primary" size="sm">Bind + grant cap</.button>
          </div>
        </.form>
      </.card>

      <.card>
        <:header>Current bindings ({length(@bindings)})</:header>
        <p :if={@bindings == []} class="text-zinc-500 italic text-sm">
          No bindings yet. Unbound Feishu users see the bot react with EYES — bind them above to enable chat.
        </p>
        <table :if={@bindings != []} class="w-full text-sm">
          <thead class="bg-zinc-50 dark:bg-zinc-950 border-b border-zinc-200 dark:border-zinc-800">
            <tr class="text-left text-xs uppercase tracking-wide text-zinc-500">
              <th class="px-2 py-2">open_id</th>
              <th class="py-2">user_uri</th>
              <th class="py-2">bound_by</th>
              <th class="py-2">when</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={b <- @bindings} class="border-b border-zinc-100 dark:border-zinc-900 last:border-0">
              <td class="px-2 py-2 font-mono text-xs">{b.open_id}</td>
              <td class="py-2 font-mono text-xs">{b.user_uri}</td>
              <td class="py-2 font-mono text-xs text-zinc-500">{b.bound_by}</td>
              <td class="py-2 text-xs text-zinc-500">{DateTime.to_iso8601(b.bound_at)}</td>
              <td class="py-2 text-right pr-2">
                <.button variant="danger" size="sm" phx-click="unbind" phx-value-open-id={b.open_id}>
                  unbind
                </.button>
              </td>
            </tr>
          </tbody>
        </table>
      </.card>
        </div>
      </:main_window>
    </IdeShell.ide_shell>
    """
  end
end
