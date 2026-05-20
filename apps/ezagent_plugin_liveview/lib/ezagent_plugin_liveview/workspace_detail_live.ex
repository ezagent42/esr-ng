defmodule EzagentPluginLiveview.WorkspaceDetailLive do
  @moduledoc """
  /workspaces/:name — single Workspace view.

  Sections:
  1. Header: name + URI + live status
  2. Members: list + add-by-URI form + per-row remove button
  3. Session templates (Phase 4d: read-only; Phase 5 editor)
  4. Routing rules (Phase 4d: read-only; Phase 5 editor)

  Member mutations go through `Ezagent.Workspace.add_member/2` and
  `remove_member/2` — both persist (Store) + dispatch (live Kind) so
  the UI shows the new state immediately AND restart-safe.
  """

  use Phoenix.LiveView
  alias EzagentDomainUi.IdeShell
  import Phoenix.Component

  @impl true
  def mount(%{"name" => name}, _session, socket) do
    case Ezagent.Workspace.Store.get_by_name(name) do
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
         # Phase 5 PR 2: selected_class is "<template_name>" for any
         # registered Class implementing Ezagent.UI.Form, or "__json__"
         # for the JSON escape hatch. Default is first registered Class.
         |> assign(:selected_class, default_selected_class())
         |> assign(:form_classes, Ezagent.UI.Form.list_form_classes())
         |> assign(:add_form, to_form(%{"member_uri" => ""}, as: "add_member"))
         |> assign(:add_template_form, to_form(%{"tmpl_name" => ""}, as: "add_template"))
         |> assign(:registered_template_classes, Ezagent.TemplateRegistry.registered_template_names())}
    end
  end

  defp default_selected_class do
    case Ezagent.UI.Form.list_form_classes() do
      [{name, _, _} | _] -> name
      [] -> "__json__"
    end
  end

  defp template_class_name(%{"class" => name}) when is_binary(name), do: name
  defp template_class_name(_), do: "—"

  defp template_member_count(%{"members" => m}) when is_list(m), do: length(m)
  defp template_member_count(_), do: 0

  defp template_status(%{"class" => name}) when is_binary(name) do
    case Ezagent.TemplateRegistry.lookup(name) do
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

  defp input_style_for(:path),
    do: "padding: 5px 8px; border: 1px solid #d1d5da; border-radius: 4px; font-size: 12px; font-family: monospace;"

  defp input_style_for(:uri),
    do: "padding: 5px 8px; border: 1px solid #d1d5da; border-radius: 4px; font-size: 12px; font-family: monospace;"

  defp input_style_for(_),
    do: "padding: 5px 8px; border: 1px solid #d1d5da; border-radius: 4px; font-size: 12px;"

  defp tmpl_mode_btn_style(true),
    do: "padding: 4px 12px; background: #0969da; color: white; border: none; border-radius: 4px; cursor: pointer; font-size: 11px;"

  defp tmpl_mode_btn_style(false),
    do: "padding: 4px 12px; background: white; color: #0969da; border: 1px solid #d1d5da; border-radius: 4px; cursor: pointer; font-size: 11px;"

  @impl true
  def handle_event("add_member", %{"add_member" => %{"member_uri" => uri_str}}, socket)
      when is_binary(uri_str) and uri_str != "" do
    case URI.new(String.trim(uri_str)) do
      {:ok, %URI{scheme: scheme} = uri} when is_binary(scheme) ->
        case Ezagent.Workspace.add_member(socket.assigns.name, uri) do
          :ok ->
            {:noreply,
             socket
             |> assign(:workspace, Ezagent.Workspace.Store.get_by_name(socket.assigns.name))
             |> assign(:add_form, to_form(%{"member_uri" => ""}, as: "add_member"))
             |> assign(:flash_error, nil)}

          {:error, reason} ->
            {:noreply, assign(socket, :flash_error, "add failed: #{inspect(reason)}")}
        end

      _ ->
        {:noreply, assign(socket, :flash_error, "URI must include a scheme (e.g. entity://agent/cc_x)")}
    end
  end

  def handle_event("add_member", _params, socket) do
    {:noreply, assign(socket, :flash_error, "Member URI is required.")}
  end

  # Phase 5 PR 2: Class picker drives form_fields/0 rendering.
  def handle_event("select_template_class", %{"class" => class_name}, socket) do
    {:noreply, assign(socket, :selected_class, class_name)}
  end

  # JSON escape hatch — Class is read from JSON's "class" field.
  def handle_event(
        "add_template",
        %{"add_template" => params},
        %{assigns: %{selected_class: "__json__"}} = socket
      ) do
    tmpl_name = Map.get(params, "tmpl_name", "") |> String.trim()
    json = Map.get(params, "json", "")

    case {tmpl_name, Jason.decode(json)} do
      {"", _} ->
        {:noreply, assign(socket, :flash_error, "template name required")}

      {_, {:ok, tmpl}} when is_map(tmpl) ->
        do_add_template(socket, tmpl_name, tmpl)

      {_, {:ok, _}} ->
        {:noreply, assign(socket, :flash_error, "JSON must be an object")}

      {_, {:error, _}} ->
        {:noreply, assign(socket, :flash_error, "invalid JSON")}
    end
  end

  # Dynamic class-driven form — delegates translation to the Class's
  # form_to_args/1 (or default_form_to_args if not overridden).
  def handle_event(
        "add_template",
        %{"add_template" => params},
        %{assigns: %{selected_class: class_name}} = socket
      ) do
    tmpl_name = Map.get(params, "tmpl_name", "") |> String.trim()

    cond do
      tmpl_name == "" ->
        {:noreply, assign(socket, :flash_error, "template name required")}

      true ->
        case Ezagent.TemplateRegistry.lookup(class_name) do
          {:ok, class_module} ->
            tmpl =
              if function_exported?(class_module, :form_to_args, 1) do
                class_module.form_to_args(params)
              else
                Ezagent.UI.Form.default_form_to_args(class_module, Map.drop(params, ["tmpl_name"]))
              end

            do_add_template(socket, tmpl_name, tmpl)

          :error ->
            {:noreply, assign(socket, :flash_error, "no registered Class: #{class_name}")}
        end
    end
  end

  defp do_add_template(socket, tmpl_name, tmpl) do
    case Ezagent.Workspace.add_template(socket.assigns.name, tmpl_name, tmpl) do
      :ok ->
        # Trigger Class.instantiate so the Session goes live immediately
        # (Loader path runs on boot; this is the runtime path).
        _ = trigger_instantiate(socket.assigns.name, tmpl_name, tmpl)

        {:noreply,
         socket
         |> assign(:workspace, Ezagent.Workspace.Store.get_by_name(socket.assigns.name))
         |> assign(:add_template_form, to_form(%{"tmpl_name" => ""}, as: "add_template"))
         |> assign(:flash_error, nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :flash_error, "add_template failed: #{inspect(reason)}")}
    end
  end

  defp trigger_instantiate(workspace_name, tmpl_name, tmpl) do
    workspace_uri = Ezagent.Entity.Workspace.uri_for(workspace_name)

    case tmpl["class"] do
      class_name when is_binary(class_name) ->
        case Ezagent.TemplateRegistry.lookup(class_name) do
          {:ok, class_module} ->
            class_module.instantiate(tmpl_name, tmpl, workspace_uri)

          :error ->
            {:error, {:no_template_class, class_name}}
        end

      _ ->
        {:error, :missing_class}
    end
  end

  def handle_event("remove_template", %{"name" => tmpl_name}, socket) do
    case Ezagent.Workspace.remove_template(socket.assigns.name, tmpl_name) do
      :ok ->
        {:noreply,
         socket
         |> assign(:workspace, Ezagent.Workspace.Store.get_by_name(socket.assigns.name))
         |> assign(:flash_error, nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :flash_error, "remove_template failed: #{inspect(reason)}")}
    end
  end

  def handle_event("remove_member", %{"member_uri" => uri_str}, socket) do
    case URI.new(uri_str) do
      {:ok, uri} ->
        case Ezagent.Workspace.remove_member(socket.assigns.name, uri) do
          :ok ->
            {:noreply,
             socket
             |> assign(:workspace, Ezagent.Workspace.Store.get_by_name(socket.assigns.name))
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
      <p><a href="/workspaces" style="color: #0969da;">← Workspaces</a></p>
    </div>
    """
  end

  def render(assigns) do
    # Phase 8 阶段 C: wrap in IdeShell.
    assigns =
      assign_new(assigns, :current_entity_uri_str, fn ->
        URI.to_string(assigns.current_entity_uri || URI.parse("entity://user/admin"))
      end)

    ~H"""
    <IdeShell.ide_shell
      current_entity_uri={@current_entity_uri_str}
      current_path={"/workspaces/" <> @workspace.name}
      status={%{agents_alive: 0, bridges: 0, debug_events: 0, version: "dev"}}
    >
      <:resource_panel>
        <div class="p-3">
          <div class="text-[10px] uppercase tracking-wide text-zinc-500 mb-2">Workspace</div>
          <div class="px-2 py-1 text-xs bg-zinc-100 rounded font-mono">{@workspace.name}</div>
          <a href="/workspaces" class="block mt-3 px-2 py-1 text-xs text-zinc-600 hover:text-zinc-900">← All workspaces</a>
        </div>
      </:resource_panel>
      <:main_window>
        <div class="flex-1 overflow-auto px-6 py-6 text-zinc-900">
        <header>
        <h1 style="font-size: 22px; font-weight: 600;">
          Workspace: <code>{@workspace.name}</code>
        </h1>
        <p style="font-size: 13px; color: #666;">
          <code>{URI.to_string(@workspace.uri)}</code>
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
            placeholder="entity://agent/cc_architect"
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
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={{tmpl_name, tmpl_data} <- @workspace.session_templates} style="border-bottom: 1px solid #f0f0f0;">
              <td style="padding: 4px 4px; font-weight: 500;">{tmpl_name}</td>
              <td style="font-family: monospace; font-size: 11px;">{template_class_name(tmpl_data)}</td>
              <td>{template_member_count(tmpl_data)}</td>
              <td style={template_status_style(template_status(tmpl_data))}>{template_status_label(template_status(tmpl_data))}</td>
              <td>
                <button
                  type="button"
                  phx-click="remove_template"
                  phx-value-name={tmpl_name}
                  style="padding: 3px 8px; background: white; color: #cf222e; border: 1px solid #cf222e; border-radius: 4px; cursor: pointer; font-size: 10px;"
                  data-confirm="Remove this template? (already-spawned Kinds stay alive)"
                >Remove</button>
              </td>
            </tr>
          </tbody>
        </table>
        <p :if={@registered_template_classes != []} id="registered-classes" style="margin-top: 12px; font-size: 11px; color: #57606a;">
          Registered Template Classes: <code>{Enum.join(@registered_template_classes, ", ")}</code>
        </p>

        <div id="add-template" style="margin-top: 16px; padding-top: 16px; border-top: 1px solid #eaeef2;">
          <h3 style="font-size: 13px; font-weight: 500; margin: 0 0 8px 0;">Add template</h3>

          <p style="font-size: 11px; color: #57606a; margin: 0 0 8px 0;">
            Class picker drives the form below — each registered Template Class self-describes its
            fields via <code>Ezagent.UI.Form.form_fields/0</code>. JSON mode is the escape hatch for
            custom Classes that don't implement the form behaviour.
          </p>

          <div style="margin-bottom: 12px; display: flex; gap: 6px; flex-wrap: wrap;">
            <button
              :for={{class_name, _module, _fields} <- @form_classes}
              type="button"
              phx-click="select_template_class"
              phx-value-class={class_name}
              style={tmpl_mode_btn_style(@selected_class == class_name)}
            >{class_name}</button>
            <button
              type="button"
              phx-click="select_template_class"
              phx-value-class="__json__"
              style={tmpl_mode_btn_style(@selected_class == "__json__")}
            >JSON (custom class)</button>
          </div>

          <.form for={@add_template_form} phx-submit="add_template">
            <div style="display: grid; grid-template-columns: 200px 1fr; gap: 6px; margin-bottom: 12px;">
              <input
                type="text"
                name="add_template[tmpl_name]"
                placeholder="template name (e.g. main)"
                style="padding: 5px 8px; border: 1px solid #d1d5da; border-radius: 4px; font-size: 12px;"
              />
              <span style="font-size: 11px; color: #57606a; align-self: center;">
                Class = <code>{@selected_class}</code>
              </span>
            </div>

            <%= if @selected_class == "__json__" do %>
              <div style="margin-bottom: 8px;">
                <textarea
                  name="add_template[json]"
                  rows="5"
                  placeholder={~s({"class":"some.class","field":"value"})}
                  style="width: 100%; padding: 6px 10px; border: 1px solid #d1d5da; border-radius: 4px; font-family: monospace; font-size: 11px;"
                ></textarea>
                <p style="font-size: 10px; color: #57606a; margin: 4px 0 0;">
                  Full template JSON — "class" field must reference a registered Class.
                </p>
              </div>
            <% else %>
              <% selected_fields =
                Enum.find_value(@form_classes, [], fn {n, _m, fields} ->
                  if n == @selected_class, do: fields
                end) %>

              <div :for={field <- selected_fields} style="display: grid; grid-template-columns: 200px 1fr; gap: 6px; margin-bottom: 8px;">
                <label style="font-size: 12px; color: #57606a; align-self: center;">
                  {field.label}{if Map.get(field, :required, false), do: " *", else: ""}
                </label>
                <%= case field.type do %>
                  <% :select -> %>
                    <select
                      name={"add_template[" <> field.name <> "]"}
                      style="padding: 5px 8px; border: 1px solid #d1d5da; border-radius: 4px; font-size: 12px; font-family: monospace;"
                    >
                      <option :for={opt <- Map.get(field, :options, [])} value={opt}>{opt}</option>
                    </select>
                  <% :path -> %>
                    <div style="display: flex; flex-direction: column; gap: 2px;">
                      <input
                        type="text"
                        name={"add_template[" <> field.name <> "]"}
                        placeholder={Map.get(field, :placeholder, "/path/to/dir")}
                        style={input_style_for(field.type)}
                      />
                      <span style="font-size: 10px; color: #57606a;">📁 Filesystem path (server-side)</span>
                    </div>
                  <% _ -> %>
                    <input
                      type="text"
                      name={"add_template[" <> field.name <> "]"}
                      placeholder={Map.get(field, :placeholder, "")}
                      style={input_style_for(field.type)}
                    />
                <% end %>
              </div>
            <% end %>

            <button
              type="submit"
              style="padding: 5px 14px; background: #1f883d; color: white; border: none; border-radius: 4px; cursor: pointer; font-size: 12px;"
            >Add template</button>
          </.form>
        </div>
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
      </:main_window>
    </IdeShell.ide_shell>
    """
  end
end
