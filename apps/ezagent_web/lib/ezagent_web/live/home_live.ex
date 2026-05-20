defmodule EzagentWeb.HomeLive do
  @moduledoc """
  Root `/` LiveView — login gate + first-login wizard.

  ## Three-way mount

  - **No session cookie** (`current_entity_uri` absent) → redirect `/login`.
  - **Authenticated AND ≥1 session in `EzagentDomainChat.list_sessions/0`** →
    redirect `/sessions` (the default app surface, unchanged from Phase 8).
  - **Authenticated AND no sessions exist** → render the first-login
    wizard inline. Operator picks a short name (default "main") and
    submits; we call `EzagentDomainChat.create_session/2` (which spawns
    + binds workspace + joins admin) and then push_navigate to
    `/sessions`.

  ## Phase 8c PR-J context

  Before PR-J, `session://main` was a static supervisor child of
  `EzagentDomainChat.Application` — hardcoded outside the canonical
  creation flow (`Session.spawn_from_template/2` / `create_session/2`).
  That bypass forced two boot-time workarounds (workspace bind +
  admin-join post-boot dispatch). PR-J drops the static child; the
  wizard is the production creation path for the default session,
  and every session in the system flows through the same API.

  ## Why a single-input wizard

  Allen's brief 2026-05-20: "99% of users just press one button". The
  form pre-fills "main" so the default flow is literally one click.
  Power users can pick a different name. No workspace picker yet —
  every new session lands on `workspace://default` per the canonical
  binding. Future enhancement: workspace selector when multi-workspace
  becomes a meaningful surface.
  """
  use EzagentWeb, :live_view

  @impl true
  def mount(_params, session, socket) do
    case session do
      %{"current_entity_uri" => entity_uri_str} when is_binary(entity_uri_str) ->
        mount_authenticated(entity_uri_str, socket)

      _ ->
        {:ok, push_navigate(socket, to: "/login")}
    end
  end

  defp mount_authenticated(entity_uri_str, socket) do
    case EzagentDomainChat.list_sessions() do
      [] ->
        # No sessions yet — render the wizard.
        socket =
          socket
          |> assign(:current_entity_uri_str, entity_uri_str)
          |> assign(:flash_error, nil)
          |> assign(:form, to_form(%{"short_name" => "main"}, as: "wizard"))

        {:ok, socket, layout: false}

      [_ | _] ->
        # At least one session exists → existing redirect behavior.
        {:ok, push_navigate(socket, to: "/sessions")}
    end
  end

  @impl true
  def handle_event("create_default_session", %{"wizard" => params}, socket) do
    short_name = params |> Map.get("short_name", "main") |> String.trim()

    if short_name == "" do
      {:noreply, assign(socket, :flash_error, "Session name is required.")}
    else
      creator_uri = parse_entity_uri(socket.assigns.current_entity_uri_str)

      case EzagentDomainChat.create_session(short_name, creator_uri) do
        {:ok, _session_uri} ->
          {:noreply, push_navigate(socket, to: "/sessions")}

        {:error, reason} ->
          {:noreply,
           assign(
             socket,
             :flash_error,
             "Create failed: #{inspect(reason)}"
           )}
      end
    end
  end

  # Defensive parser — LiveAuth already validated this string at session
  # mount, but HomeLive lives outside the `:require_entity` live_session,
  # so re-parse here. Fall back to admin if the cookie is malformed
  # (LiveAuth would have caught it earlier on protected routes; here
  # we let the wizard proceed under admin caps so the operator isn't
  # locked out of their own setup).
  defp parse_entity_uri(uri_str) when is_binary(uri_str) do
    case URI.new(uri_str) do
      {:ok, %URI{scheme: "entity"} = uri} -> uri
      _ -> Ezagent.Entity.User.admin_uri()
    end
  end

  defp parse_entity_uri(_), do: Ezagent.Entity.User.admin_uri()

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center bg-zinc-50 dark:bg-zinc-950 px-4">
      <div class="w-full max-w-md">
        <div class="text-center mb-8">
          <h1 class="text-2xl font-semibold text-zinc-900 dark:text-zinc-100">
            Welcome to ezagent
          </h1>
          <p class="mt-2 text-sm text-zinc-500">
            Let's set up your first session.
          </p>
        </div>

        <div class="bg-white dark:bg-zinc-900 rounded-md border border-zinc-200 dark:border-zinc-800 shadow-sm p-6">
          <.form
            for={@form}
            id="first-session-wizard"
            phx-submit="create_default_session"
            class="space-y-4"
          >
            <div>
              <label
                for="wizard_short_name"
                class="block text-sm font-medium text-zinc-700 dark:text-zinc-300 mb-1"
              >
                Session short name
              </label>
              <input
                type="text"
                name="wizard[short_name]"
                id="wizard_short_name"
                value={@form[:short_name].value}
                placeholder="main"
                autocomplete="off"
                class="w-full px-3 py-2 text-sm bg-white dark:bg-zinc-950 border border-zinc-300 dark:border-zinc-700 rounded-md text-zinc-900 dark:text-zinc-100 focus:outline-none focus:border-zinc-500 dark:focus:border-zinc-500"
              />
              <p class="mt-1 text-xs text-zinc-500">
                Creates <span class="font-mono">session://<span id="short-name-preview">{@form[:short_name].value}</span></span> bound to <span class="font-mono">workspace://default</span>.
              </p>
            </div>

            <div :if={@flash_error} class="text-sm text-red-600 dark:text-red-400">
              {@flash_error}
            </div>

            <button
              type="submit"
              class="w-full px-4 py-2 text-sm font-medium bg-zinc-900 dark:bg-zinc-100 text-white dark:text-zinc-900 rounded-md hover:bg-zinc-800 dark:hover:bg-zinc-200 transition-colors"
            >
              Create session
            </button>
          </.form>
        </div>

        <p class="mt-6 text-center text-xs text-zinc-500">
          Signed in as <span class="font-mono">{@current_entity_uri_str}</span>
        </p>
      </div>
    </div>
    """
  end
end
