defmodule EzagentPluginLiveview.Views.ConversationView do
  @moduledoc """
  Phase 8b — default Session view: chat message stream.

  Renders the `@messages_stream` (owned by the wrapping admin_live)
  inside the SessionEditor's main area. Applies to every session
  (every session has a conversation, even if empty).

  Implements `Ezagent.UI.SessionView`. Registered by
  `EzagentPluginLiveview.Application.start/2`.
  """

  @behaviour Ezagent.UI.SessionView
  use Phoenix.Component

  @impl true
  def id, do: :conversation

  @impl true
  def label, do: "Chat"

  @impl true
  def icon, do: "message-square"

  @impl true
  # Every session has a conversation view.
  def applies_to?(_session_uri), do: true

  @impl true
  def render(assigns) do
    # Phase 8c PR-B (Allen 2026-05-20) — empty-state aware. When the
    # session has zero messages, the main area is otherwise a blank
    # white expanse; replace it with a subtle dot-grid + minimal
    # affordance so it reads as "this is where messages will appear",
    # not "is this page broken?". Inferred from `@empty_state?` which
    # admin_live computes from the stream (stays nil during render
    # while stream hasn't been touched).
    assigns =
      assigns
      |> assign_new(:empty_state?, fn ->
        # default: assume non-empty (admin_live overrides when known)
        false
      end)

    ~H"""
    <div class="flex-1 flex flex-col min-h-0">
      <div :if={@oldest_cursor} class="text-center py-1 bg-zinc-50 border-b border-zinc-200 shrink-0">
        <button
          type="button"
          id="load-older-btn"
          phx-click="load_older_messages"
          class="px-3 py-1 bg-white text-blue-600 border border-zinc-300 rounded text-xs hover:bg-zinc-50"
        >
          ↑ Load older
        </button>
      </div>

      <%!-- Empty state — refined minimalism: subtle dot-grid background,
            no clip art, a small monospace caption that names what this
            surface IS. Disappears the moment a real message lands. --%>
      <div
        :if={@empty_state?}
        class="flex-1 flex items-center justify-center"
        style="background-image: radial-gradient(circle, #e4e4e7 1px, transparent 1px); background-size: 16px 16px;"
      >
        <div class="text-center">
          <div class="font-mono text-xs uppercase tracking-widest text-zinc-400">
            empty session
          </div>
          <div class="mt-2 text-sm text-zinc-500">
            Type a message below to begin.
          </div>
        </div>
      </div>

      <div
        :if={not @empty_state?}
        id="messages"
        phx-update="stream"
        phx-hook="ScrollOnUpdate"
        class="flex-1 overflow-y-auto px-4 py-3 bg-zinc-50 space-y-2"
      >
        <div
          :for={{dom_id, row} <- @messages_stream}
          id={dom_id}
          class={[
            "max-w-2xl rounded-lg px-3 py-2 border",
            row.sender_kind == :user && "bg-blue-50 border-blue-200 ml-auto",
            row.sender_kind == :agent && "bg-emerald-50 border-emerald-200 mr-auto",
            row.sender_kind == :other && "bg-zinc-100 border-zinc-200 mx-auto"
          ]}
        >
          <div class="flex items-center gap-2 text-[11px] text-zinc-500">
            <span class="font-mono">{row.sender}</span>
            <span>·</span>
            <span>{format_time(row.at)}</span>
          </div>
          <div :if={row.text != ""} class="mt-1 text-sm whitespace-pre-wrap break-words">{row.text}</div>
          <div :if={attachments_of(row) != []} class="mt-2 flex gap-1 flex-wrap">
            <a
              :for={{name, href} <- attachments_of(row)}
              href={href}
              target="_blank"
              class="inline-flex items-center gap-1 px-2 py-1 bg-white border border-zinc-200 rounded text-xs text-blue-600 hover:bg-zinc-50"
            >
              📎 {name}
            </a>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M")
  defp format_time(_), do: ""

  defp attachments_of(%{attachments: list}) when is_list(list), do: list
  defp attachments_of(_), do: []
end
