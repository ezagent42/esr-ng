defmodule EsrWebLiveview.Admin.MemberPanel do
  @moduledoc """
  Right pane: session members table (uri / online / last_seen).
  Stateless — parent (AdminLive) reads members from the Session Kind
  via :sys.get_state and refreshes on member_joined/member_left/member_offline.
  """

  use Phoenix.Component

  attr :members, :list, required: true

  def member_panel(assigns) do
    ~H"""
    <aside id="session-members" style="border-left: 1px solid #eaeef2; padding-left: 16px;">
      <h3 style="font-size: 14px; font-weight: 500; margin: 0 0 8px 0;">Members</h3>
      <p :if={@members == []} id="session-members-empty" style="font-size: 12px; color: #57606a;">
        (No members — Chat plugin failed to start?)
      </p>
      <table :if={@members != []} id="session-members-table" style="width: 100%; font-size: 12px; border-collapse: collapse;">
        <tbody>
          <tr :for={member <- @members} style="border-bottom: 1px solid #f0f0f0;">
            <td style="padding: 4px 0;">
              <div style="font-family: monospace; font-size: 11px;">{member.uri}</div>
              <div style={member_status_style(member.online)}>
                {if member.online, do: "online", else: "offline"}
                <span :if={member.last_seen} style="color: #999; font-weight: normal;">
                  · {DateTime.to_iso8601(member.last_seen)}
                </span>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </aside>
    """
  end

  defp member_status_style(true), do: "font-size: 11px; color: #1f883d; font-weight: 600;"
  defp member_status_style(false), do: "font-size: 11px; color: #999;"
end
