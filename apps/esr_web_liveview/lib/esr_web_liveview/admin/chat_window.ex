defmodule EsrWebLiveview.Admin.ChatWindow do
  @moduledoc """
  Center pane: session header + message stream + compose form.
  Stateless — parent (AdminLive) owns the :messages stream, compose form,
  and the chat_compose event handler. The `messages` slot receives the
  stream entries so this component stays a pure renderer.
  """

  use Phoenix.Component

  attr :current_session_uri, URI, required: true
  attr :messages_stream, :any, required: true
  attr :agent_options, :list, required: true
  attr :compose_form, :map, required: true
  attr :flash_error, :string, default: nil

  def chat_window(assigns) do
    ~H"""
    <div>
      <h2 style="font-size: 16px; font-weight: 500; margin: 0 0 8px 0;">
        Session: <code>{URI.to_string(@current_session_uri)}</code>
      </h2>

      <div
        id="messages"
        phx-update="stream"
        phx-hook="ScrollOnUpdate"
        style="height: 360px; overflow-y: auto; border: 1px solid #d1d5da; border-radius: 4px; padding: 12px; background: #fafbfc;"
      >
        <div :for={{dom_id, row} <- @messages_stream} id={dom_id} style={message_row_style(row.sender_kind)}>
          <div style="font-family: monospace; font-size: 11px; color: #57606a;">
            [{row.sender}] · {DateTime.to_iso8601(row.at)}
          </div>
          <div style="margin-top: 2px; white-space: pre-wrap;">{row.text}</div>
        </div>
      </div>

      <.form
        for={@compose_form}
        phx-submit="chat_compose"
        style="display: flex; gap: 8px; align-items: end; margin-top: 12px;"
      >
        <div style="flex: 0 0 240px;">
          <label style="display: block; font-size: 13px; font-weight: 500;" for="chat_agent_uri">@ agent</label>
          <select
            name="chat[agent_uri]"
            id="chat_agent_uri"
            style="width: 100%; padding: 6px 10px; border: 1px solid #d1d5da; border-radius: 4px;"
          >
            <option value="">— room (no mention) —</option>
            <option :for={uri <- @agent_options} value={uri}>{uri}</option>
          </select>
          <p :if={@agent_options == []} style="font-size: 11px; color: #999; margin: 4px 0 0;">
            (no agents in this session — add one via Floating list)
          </p>
        </div>
        <div style="flex: 1 1 auto;">
          <label style="display: block; font-size: 13px; font-weight: 500;" for="chat_text">message</label>
          <input
            type="text"
            name="chat[text]"
            id="chat_text"
            value=""
            autocomplete="off"
            style="width: 100%; padding: 6px 10px; border: 1px solid #d1d5da; border-radius: 4px;"
          />
        </div>
        <button
          type="submit"
          id="chat-send-btn"
          style="padding: 8px 16px; background: #1f883d; color: white; border: none; border-radius: 4px; cursor: pointer;"
        >
          Send
        </button>
      </.form>
      <p :if={@flash_error} style="color: #cf222e; font-size: 13px; margin-top: 8px;">{@flash_error}</p>
    </div>
    """
  end

  # SAME DOM shape, only wrapper bg differs (Phase 2 visual invariant).
  defp message_row_style(:user),
    do: "padding: 8px 10px; margin-bottom: 6px; background: #ddf4ff; border-radius: 4px;"

  defp message_row_style(:agent),
    do: "padding: 8px 10px; margin-bottom: 6px; background: #dafbe1; border-radius: 4px;"

  defp message_row_style(_),
    do: "padding: 8px 10px; margin-bottom: 6px; background: #f6f8fa; border-radius: 4px;"
end
