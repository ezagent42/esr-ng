defmodule EzagentPluginLiveview.UsersLive do
  @moduledoc """
  /admin/users — list + create + disable Users (Phase 5 PR 2).

  Admin-only surface (route gate via RequireUser). Backed by `Ezagent.Users`
  (Phase 4-completion PR 4) — separate from User-Kind snapshot per
  Q-MU-2.
  """

  use Phoenix.LiveView
  import Phoenix.Component

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:users, list_users())
     |> assign(:flash_error, nil)
     |> assign(:flash_info, nil)
     |> assign(:create_form, to_form(create_form_defaults(), as: "user"))}
  end

  defp create_form_defaults do
    %{"uri" => "user://", "password" => "", "caps" => ""}
  end

  defp list_users do
    Ezagent.Users.list_all()
    |> Enum.map(fn u ->
      Map.merge(u, %{
        has_password: not is_nil(u.password_hash),
        cap_count: length(u.caps)
      })
    end)
  end

  @impl true
  def handle_event("create_user", %{"user" => params}, socket) do
    uri = Map.get(params, "uri", "") |> String.trim()
    password = Map.get(params, "password", "")
    caps_str = Map.get(params, "caps", "")

    cond do
      uri == "" or uri == "user://" ->
        {:noreply, assign(socket, :flash_error, "User URI required (e.g. user://allen)")}

      String.contains?(caps_str, "*") ->
        {:noreply,
         assign(socket, :flash_error,
           "'*' caps require --allow-allcaps via mix; UI refuses for safety"
         )}

      true ->
        with {:ok, _uri} <- parse_user_uri(uri),
             {:ok, caps} <-
               Ezagent.Capability.Parser.parse(caps_str, Ezagent.Entity.User.admin_uri()),
             pw = if(password == "", do: nil, else: password),
             {:ok, _decoded} <- Ezagent.Users.create(uri, pw, caps) do
          _ = maybe_spawn_kind(uri)

          {:noreply,
           socket
           |> assign(:users, list_users())
           |> assign(:flash_info, "✓ created #{uri} (#{length(caps)} caps)")
           |> assign(:flash_error, nil)
           |> assign(:create_form, to_form(create_form_defaults(), as: "user"))}
        else
          {:error, reason} ->
            {:noreply, assign(socket, :flash_error, "create failed: #{inspect(reason)}")}
        end
    end
  end

  def handle_event("set_password", %{"uri" => uri, "password" => password}, socket)
      when is_binary(password) and password != "" do
    case Ezagent.Users.set_password(uri, password) do
      {:ok, _} ->
        {:noreply,
         socket
         |> assign(:users, list_users())
         |> assign(:flash_info, "✓ password set for #{uri}")
         |> assign(:flash_error, nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :flash_error, "set_password failed: #{inspect(reason)}")}
    end
  end

  def handle_event("set_password", _params, socket) do
    {:noreply, assign(socket, :flash_error, "password cannot be empty")}
  end

  defp parse_user_uri(s) do
    case URI.new(s) do
      {:ok, %URI{scheme: "user", host: host}} when is_binary(host) and host != "" ->
        {:ok, URI.parse(s)}

      _ ->
        {:error, {:bad_user_uri, s}}
    end
  end

  defp maybe_spawn_kind(uri_str) do
    uri = URI.parse(uri_str)

    if Code.ensure_loaded?(Ezagent.SpawnRegistry) do
      _ = Ezagent.SpawnRegistry.spawn(uri)
    end

    :ok
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div style="max-width: 1000px; margin: 0 auto; padding: 24px; font-family: -apple-system, sans-serif;">
      <header>
        <h1 style="font-size: 22px; font-weight: 600;">Users</h1>
        <p style="font-size: 13px; color: #666;">
          Provisioned principals (independent of User Kind snapshot per Q-MU-2).
          <a href="/admin" style="margin-left: 16px; color: #0969da;">← /admin</a>
        </p>
      </header>

      <section id="users-list" style="margin-top: 16px;">
        <p :if={@users == []} style="color: #57606a; font-style: italic;">No users.</p>

        <table :if={@users != []} id="users-table" style="width: 100%; font-size: 13px; border-collapse: collapse;">
          <thead>
            <tr style="border-bottom: 2px solid #d1d5da;">
              <th style="text-align: left; padding: 6px 4px;">URI</th>
              <th style="text-align: left;">Password set?</th>
              <th style="text-align: left;">Caps</th>
              <th style="text-align: left;">Set password</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={u <- @users} style="border-bottom: 1px solid #eaeef2;">
              <td style="padding: 6px 4px; font-family: monospace; font-size: 12px;">{URI.to_string(u.uri)}</td>
              <td style="font-size: 11px;">
                <span :if={u.has_password} style="color: #1f883d;">● set</span>
                <span :if={!u.has_password} style="color: #cf222e;">○ (must set before login)</span>
              </td>
              <td style="font-size: 11px;">{u.cap_count}</td>
              <td>
                <form phx-submit="set_password" style="display: flex; gap: 4px;">
                  <input type="hidden" name="uri" value={URI.to_string(u.uri)} />
                  <input
                    type="password"
                    name="password"
                    placeholder="new password"
                    style="padding: 4px 8px; border: 1px solid #d1d5da; border-radius: 4px; font-size: 11px; width: 130px;"
                  />
                  <button
                    type="submit"
                    style="padding: 4px 10px; background: white; color: #0969da; border: 1px solid #0969da; border-radius: 4px; cursor: pointer; font-size: 11px;"
                  >Set</button>
                </form>
              </td>
            </tr>
          </tbody>
        </table>
      </section>

      <section id="create-user" style="margin-top: 24px; padding: 16px; border: 1px solid #d1d5da; border-radius: 6px;">
        <h2 style="font-size: 14px; font-weight: 500; margin: 0 0 12px 0;">+ Create user</h2>

        <.form for={@create_form} phx-submit="create_user">
          <div style="display: grid; grid-template-columns: 250px 200px 1fr 120px; gap: 8px;">
            <input
              type="text"
              name="user[uri]"
              placeholder="user://allen"
              value={@create_form.params["uri"]}
              style="padding: 6px 10px; border: 1px solid #d1d5da; border-radius: 4px; font-family: monospace; font-size: 12px;"
            />
            <input
              type="password"
              name="user[password]"
              placeholder="password (optional)"
              style="padding: 6px 10px; border: 1px solid #d1d5da; border-radius: 4px; font-size: 12px;"
            />
            <input
              type="text"
              name="user[caps]"
              placeholder="caps (e.g. chat.send,workspace.read)"
              style="padding: 6px 10px; border: 1px solid #d1d5da; border-radius: 4px; font-family: monospace; font-size: 12px;"
            />
            <button
              type="submit"
              style="padding: 6px 16px; background: #1f883d; color: white; border: none; border-radius: 4px; cursor: pointer;"
            >Create</button>
          </div>
          <p style="font-size: 11px; color: #57606a; margin-top: 6px;">
            URI scheme: <code>user://</code>. Caps grammar:
            <code>kind.behavior</code> or <code>kind.behavior@instance_uri</code>;
            comma-separated. Asterisk (<code>*</code>) requires the
            <code>--allow-allcaps</code> mix CLI flag.
          </p>
        </.form>

        <p :if={@flash_error} style="color: #cf222e; font-size: 12px; margin-top: 8px;">{@flash_error}</p>
        <p :if={@flash_info} style="color: #1f883d; font-size: 12px; margin-top: 8px;">{@flash_info}</p>
      </section>
    </div>
    """
  end
end
