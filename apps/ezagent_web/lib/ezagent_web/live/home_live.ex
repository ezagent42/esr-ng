defmodule EzagentWeb.HomeLive do
  @moduledoc """
  Root `/` redirector.

  Phase 8: redirect unauthenticated visitors to `/login`, and
  authenticated visitors straight to `/admin` (the app surface).
  Previously this was a Phase-0 placeholder LV from when the routing
  pipeline was being shaken out.
  """
  use EzagentWeb, :live_view

  @impl true
  def mount(_params, session, socket) do
    case session do
      %{"current_entity_uri" => _uri} ->
        {:ok, push_navigate(socket, to: "/admin")}

      _ ->
        {:ok, push_navigate(socket, to: "/login")}
    end
  end

  @impl true
  def render(assigns) do
    # Brief flash shown only if push_navigate hasn't taken effect yet.
    ~H"""
    <div class="min-h-screen flex items-center justify-center text-sm text-zinc-500">
      Redirecting…
    </div>
    """
  end
end
