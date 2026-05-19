defmodule EzagentPluginLiveview.Admin.ChatWindow do
  @moduledoc """
  Center pane: session header + message stream + compose form.
  Stateless — parent (AdminLive) owns the :messages stream, compose form,
  and the chat_compose event handler. The `messages` slot receives the
  stream entries so this component stays a pure renderer.
  """

  use Phoenix.Component

  attr :current_session_uri, URI, required: true
  attr :messages_stream, :any, required: true
  attr :member_options, :list, required: true
  attr :compose_form, :map, required: true
  attr :flash_error, :string, default: nil
  attr :oldest_cursor, :any, default: nil
  attr :uploads, :map, default: nil

  def chat_window(assigns) do
    ~H"""
    <div>
      <h2 style="font-size: 16px; font-weight: 500; margin: 0 0 8px 0;">
        Session: <code>{URI.to_string(@current_session_uri)}</code>
      </h2>

      <div :if={@oldest_cursor} style="text-align: center; margin-bottom: 6px;">
        <button
          type="button"
          id="load-older-btn"
          phx-click="load_older_messages"
          style="padding: 4px 12px; background: white; color: #0969da; border: 1px solid #d1d5da; border-radius: 4px; cursor: pointer; font-size: 12px;"
        >
          ↑ Load older
        </button>
      </div>

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
          <div :if={row.text != ""} style="margin-top: 2px; white-space: pre-wrap;">{row.text}</div>
          <div :if={attachments_of(row) != []} style="margin-top: 4px;">
            <a
              :for={{name, href} <- attachments_of(row)}
              href={href}
              target="_blank"
              style="display: inline-block; margin-right: 8px; padding: 3px 8px; background: white; border: 1px solid #d1d5da; border-radius: 3px; font-size: 12px; color: #0969da; text-decoration: none;"
            >
              📎 {name}
            </a>
          </div>
        </div>
      </div>

      <.form
        for={@compose_form}
        phx-submit="chat_compose"
        phx-change="validate_compose"
        style="display: flex; gap: 8px; align-items: end; margin-top: 12px; flex-wrap: wrap;"
      >
        <div style="flex: 0 0 240px;">
          <label style="display: block; font-size: 13px; font-weight: 500;" for="chat_agent_uri">@ member</label>
          <select
            name="chat[agent_uri]"
            id="chat_agent_uri"
            style="width: 100%; padding: 6px 10px; border: 1px solid #d1d5da; border-radius: 4px;"
          >
            <option value="">— room (no mention) —</option>
            <option :for={uri <- @member_options} value={uri}>{uri}</option>
          </select>
          <p :if={@member_options == []} style="font-size: 11px; color: #999; margin: 4px 0 0;">
            (no members in this session — add an agent via Floating list, or join more users)
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
        <div :if={@uploads} style="flex: 0 0 auto;">
          <label
            for={@uploads.attachments.ref}
            style="display: inline-block; padding: 8px 12px; background: white; color: #0969da; border: 1px solid #d1d5da; border-radius: 4px; cursor: pointer; font-size: 13px;"
            title="Attach files (≤10MB each, up to 5)"
          >
            📎 Attach
          </label>
          <.live_file_input upload={@uploads.attachments} style="display: none;" />
        </div>
        <button
          type="submit"
          id="chat-send-btn"
          style="padding: 8px 16px; background: #1f883d; color: white; border: none; border-radius: 4px; cursor: pointer;"
        >
          Send
        </button>

        <div :if={@uploads && @uploads.attachments.entries != []} style="flex-basis: 100%; margin-top: 6px;">
          <div
            :for={entry <- @uploads.attachments.entries}
            style="display: inline-flex; align-items: center; gap: 6px; margin: 2px 6px 2px 0; padding: 3px 8px; background: #ddf4ff; border-radius: 3px; font-size: 12px;"
          >
            <span>📎 {entry.client_name}</span>
            <span style="color: #57606a;">{progress_label(entry)}</span>
            <button
              type="button"
              phx-click="cancel_upload"
              phx-value-ref={entry.ref}
              aria-label={"cancel " <> entry.client_name}
              style="background: none; border: none; color: #cf222e; cursor: pointer; padding: 0; font-size: 14px; line-height: 1;"
            >
              ×
            </button>
          </div>
          <div :for={err <- my_upload_errors(@uploads.attachments)} style="color: #cf222e; font-size: 12px; margin-top: 2px;">
            {format_upload_error(err)}
          </div>
        </div>
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

  defp attachments_of(%{attachments: list}) when is_list(list), do: list
  defp attachments_of(_), do: []

  defp progress_label(%{progress: 100}), do: "✓"
  defp progress_label(%{progress: p}) when is_integer(p) and p > 0, do: "#{p}%"
  defp progress_label(_), do: ""

  defp my_upload_errors(%{errors: errors}) when is_list(errors), do: errors
  defp my_upload_errors(_), do: []

  defp format_upload_error({_ref, :too_large}), do: "file too large (max 10MB)"
  defp format_upload_error({_ref, :too_many_files}), do: "too many files (max 5)"
  defp format_upload_error({_ref, reason}), do: "upload error: #{inspect(reason)}"
end
