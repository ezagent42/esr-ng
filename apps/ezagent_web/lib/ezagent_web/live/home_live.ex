defmodule EzagentWeb.HomeLive do
  @moduledoc """
  Root `/` redirector.

  Phase 8 polish (Allen 2026-05-20): redirect unauthenticated visitors
  to `/login`, authenticated visitors to `/sessions` (the default app
  surface — was `/admin` before the polish IA refactor moved business
  features out of `/admin/*`).
  """
  use EzagentWeb, :live_view

  @impl true
  def mount(_params, session, socket) do
    case session do
      %{"current_entity_uri" => _uri} ->
        {:ok, push_navigate(socket, to: "/sessions")}

      _ ->
        {:ok, push_navigate(socket, to: "/login")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center text-sm text-zinc-500">
      Redirecting…
    </div>
    """
  end
end
