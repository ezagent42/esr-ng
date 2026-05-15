defmodule EsrWeb.HomeLive do
  @moduledoc """
  Phase 0 placeholder home page.

  Deliberately a minimal LiveView (not a phx.new controller page) so the
  LiveView WebSocket path is exercised end-to-end from Phase 0 — including
  from a tailnet origin (P0-D8). The whole roadmap testing model from Phase 1
  on is LiveView-driven, so proving the WS path now de-risks Phase 1.

  Replaced by the `esr_web_liveview` plugin's real IM in Phase 1.
  """
  use EsrWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-xl py-24 text-center">
        <h1 class="text-2xl font-semibold">ESR v0.4 — phase 0 complete</h1>
        <p class="mt-2 text-base-content/70">
          项目骨架 + 工具链就位。下一步:Phase 1。
        </p>
      </div>
    </Layouts.app>
    """
  end
end
