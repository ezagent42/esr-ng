defmodule EsrWebLiveview.WorkspaceDetailLive do
  @moduledoc """
  /admin/workspaces/:name — single Workspace view.

  Sections:
  1. Header: name + URI + live status
  2. Members: list + add-by-URI form + per-row remove button
  3. Session templates (Phase 4d: read-only; Phase 5 editor)
  4. Routing rules (Phase 4d: read-only; Phase 5 editor)

  Member mutations go through `Esr.Workspace.add_member/2` and
  `remove_member/2` — both persist (Store) + dispatch (live Kind) so
  the UI shows the new state immediately AND restart-safe.
  """

  use Phoenix.LiveView
  import Phoenix.Component

  @impl true
  def mount(%{"name" => name}, _session, socket) do
    case Esr.Workspace.Store.get_by_name(name) do
      nil ->
        {:ok,
         socket
         |> assign(:not_found, true)
         |> assign(:name, name)}

      ws ->
        {:ok,
         socket
         |> assign(:not_found, false)
         |> assign(:name, name)
         |> assign(:workspace, ws)
         |> assign(:flash_error, nil)
         |> assign(:add_form, to_form(%{"member_uri" => ""}, as: "add_member"))
         |> assign(:registered_template_classes, Esr.TemplateRegistry.registered_template_names())}
    end
  end

  defp template_class_name(%{"class" => name}) when is_binary(name), do: name
  defp template_class_name(_), do: "—"

  defp template_member_count(%{"members" => m}) when is_list(m), do: length(m)
  defp template_member_count(_), do: 0

  defp template_status(%{"class" => name}) when is_binary(name) do
    case Esr.TemplateRegistry.lookup(name) do
      {:ok, _module} -> :class_registered
      :error -> :no_class
    end
  end

  defp template_status(_), do: :no_class_field

  defp template_status_label(:class_registered), do: "Class registered"
  defp template_status_label(:no_class), do: "No Class registered"
  defp template_status_label(:no_class_field), do: "Missing \"class\" field"

  defp template_status_style(:class_registered),
    do: "font-size: 11px; color: #1f883d;"

  defp template_status_style(_),
    do: "font-size: 11px; color: #cf222e;"

  @impl true
  def handle_event("add_member", %{"add_member" => %{"member_uri" => uri_str}}, socket)
      when is_binary(uri_str) and uri_str != "" do
    case URI.new(String.trim(uri_str)) do
      {:ok, %URI{scheme: scheme} = uri} when is_binary(scheme) ->
        case Esr.Workspace.add_member(socket.assigns.name, uri) do
          :ok ->
            {:noreply,
             socket
             |> assign(:workspace, Esr.Workspace.Store.get_by_name(socket.assigns.name))
             |> assign(:add_form, to_form(%{"member_uri" => ""}, as: "add_member"))
             |> assign(:flash_error, nil)}

          {:error, reason} ->
            {:noreply, assign(socket, :flash_error, "add failed: #{inspect(reason)}")}
        end

      _ ->
        {:noreply, assign(socket, :flash_error, "URI must include a scheme (e.g. agent://x)")}
    end
  end

  def handle_event("add_member", _params, socket) do
    {:noreply, assign(socket, :flash_error, "Member URI is required.")}
  end

  def handle_event("remove_member", %{"member_uri" => uri_str}, socket) do
    case URI.new(uri_str) do
      {:ok, uri} ->
        case Esr.Workspace.remove_member(socket.assigns.name, uri) do
          :ok ->
            {:noreply,
             socket
             |> assign(:workspace, Esr.Workspace.Store.get_by_name(socket.assigns.name))
             |> assign(:flash_error, nil)}

          {:error, reason} ->
            {:noreply, assign(socket, :flash_error, "remove failed: #{inspect(reason)}")}
        end

      _ ->
        {:noreply, assign(socket, :flash_error, "Bad URI")}
    end
  end

  @impl true
  def render(%{not_found: true} = assigns) do
    ~H"""
    <div style="max-width: 800px; margin: 0 auto; padding: 24px; font-family: -apple-system, sans-serif;">
      <h1 style="font-size: 22px;">Workspace not found</h1>
      <p>No persisted workspace named <code>{@name}</code>.</p>
      <p><a href="/admin/workspaces" style="color: #0969da;">← Workspaces</a></p>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div style="max-width: 1000px; margin: 0 auto; padding: 24px; font-family: -apple-system, sans-serif;">
      <header>
        <h1 style="font-size: 22px; font-weight: 600;">
          Workspace: <code>{@workspace.name}</code>
        </h1>
        <p style="font-size: 13px; color: #666;">
          <code>{URI.to_string(@workspace.uri)}</code>
          <a href="/admin/workspaces" style="margin-left: 16px; color: #0969da;">← Workspaces</a>
        </p>
      </header>

      <section id="members" style="margin-top: 24px; padding: 16px; border: 1px solid #d1d5da; border-radius: 6px;">
        <h2 style="font-size: 14px; font-weight: 500; margin: 0 0 12px 0;">Members ({length(@workspace.members)})</h2>

        <p :if={@workspace.members == []} id="members-empty" style="color: #57606a; font-style: italic;">
          No members. Add one below to declare a Kind that should be alive
          whenever this Workspace is loaded.
        </p>

        <ul :if={@workspace.members != []} id="members-list" style="list-style: none; padding: 0; margin: 0;">
          <li :for={member <- @workspace.members} style="display: flex; align-items: center; padding: 6px 0; border-bottom: 1px solid #f0f0f0;">
            <code style="flex: 1; font-size: 12px;">{URI.to_string(member)}</code>
            <button
              type="button"
              phx-click="remove_member"
              phx-value-member_uri={URI.to_string(member)}
              style="padding: 4px 10px; background: white; color: #cf222e; border: 1px solid #cf222e; border-radius: 4px; cursor: pointer; font-size: 11px;"
              data-confirm="Remove this member?"
            >
              Remove
            </button>
          </li>
        </ul>

        <.form for={@add_form} phx-submit="add_member" style="display: flex; gap: 8px; margin-top: 16px;">
          <input
            type="text"
            name="add_member[member_uri]"
            id="add_member_uri"
            placeholder="agent://cc-architect"
            style="flex: 1; padding: 6px 10px; border: 1px solid #d1d5da; border-radius: 4px; font-family: monospace; font-size: 12px;"
          />
          <button
            type="submit"
            style="padding: 6px 16px; background: #0969da; color: white; border: none; border-radius: 4px; cursor: pointer;"
          >
            Add member
          </button>
        </.form>
        <p :if={@flash_error} style="color: #cf222e; font-size: 13px; margin-top: 8px;">{@flash_error}</p>
      </section>

      <section id="templates" style="margin-top: 24px; padding: 16px; border: 1px solid #d1d5da; border-radius: 6px;">
        <h2 style="font-size: 14px; font-weight: 500; margin: 0 0 12px 0;">
          Session templates ({map_size(@workspace.session_templates)})
          <span style="font-size: 11px; color: #57606a; font-weight: normal;">
            (read-only here — add via <code>mix esr.workspace.add_template</code>; LV editor Phase 5)
          </span>
        </h2>
        <p :if={@workspace.session_templates == %{}} id="templates-empty" style="color: #57606a; font-style: italic;">
          No session templates declared.
        </p>
        <table :if={@workspace.session_templates != %{}} id="templates-table" style="width: 100%; font-size: 12px; border-collapse: collapse;">
          <thead>
            <tr style="border-bottom: 1px solid #d1d5da;">
              <th style="text-align: left; padding: 6px 4px;">Name</th>
              <th style="text-align: left;">Class</th>
              <th style="text-align: left;">Members</th>
              <th style="text-align: left;">Status</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={{tmpl_name, tmpl_data} <- @workspace.session_templates} style="border-bottom: 1px solid #f0f0f0;">
              <td style="padding: 4px 4px; font-weight: 500;">{tmpl_name}</td>
              <td style="font-family: monospace; font-size: 11px;">{template_class_name(tmpl_data)}</td>
              <td>{template_member_count(tmpl_data)}</td>
              <td style={template_status_style(template_status(tmpl_data))}>{template_status_label(template_status(tmpl_data))}</td>
            </tr>
          </tbody>
        </table>
        <p :if={@registered_template_classes != []} id="registered-classes" style="margin-top: 12px; font-size: 11px; color: #57606a;">
          Registered Template Classes: <code>{Enum.join(@registered_template_classes, ", ")}</code>
        </p>
      </section>

      <section id="routing-rules" style="margin-top: 24px; padding: 16px; border: 1px solid #d1d5da; border-radius: 6px;">
        <h2 style="font-size: 14px; font-weight: 500; margin: 0 0 12px 0;">
          Routing rules ({length(@workspace.routing_rules)})
          <span style="font-size: 11px; color: #57606a; font-weight: normal;">(read-only — Phase 5 editor)</span>
        </h2>
        <p :if={@workspace.routing_rules == []} id="rules-empty" style="color: #57606a; font-style: italic;">
          No routing rules declared.
        </p>
        <pre :if={@workspace.routing_rules != []} id="rules-json" style="background: #f6f8fa; padding: 12px; border-radius: 4px; overflow-x: auto; font-size: 11px;">{Jason.encode!(@workspace.routing_rules, pretty: true)}</pre>
      </section>
    </div>
    """
  end
end
