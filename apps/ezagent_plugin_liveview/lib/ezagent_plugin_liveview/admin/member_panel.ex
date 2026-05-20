defmodule EzagentPluginLiveview.Admin.MemberPanel do
  @moduledoc """
  Right pane: session members table (uri / online / last_seen).
  Stateless — parent (AdminLive) reads members from the Session Kind
  via :sys.get_state and refreshes on member_joined/member_left/member_offline.

  Phase 8b — for every `entity://agent/cc_*` member, renders a small
  PTY (🖥️) button next to the URI. Click dispatches
  `switch_to_pty_for_agent` which sets the SessionEditor view-mode
  to `:pty` and binds xterm.js to the chosen agent.
  """

  use Phoenix.Component
  use EzagentDomainUi.Primitives

  attr :members, :list, required: true

  def member_panel(assigns) do
    ~H"""
    <aside id="session-members" class="p-3 text-zinc-800 dark:text-zinc-200">
      <h3 class="text-[10px] uppercase tracking-wide text-zinc-500 mb-2">Members</h3>
      <p :if={@members == []} id="session-members-empty" class="text-xs text-zinc-500">
        (No members — Chat plugin failed to start?)
      </p>
      <table :if={@members != []} id="session-members-table" class="w-full text-xs">
        <tbody>
          <tr :for={member <- @members} class="border-b border-zinc-100 dark:border-zinc-900">
            <td class="py-1.5 align-top">
              <div class="flex items-center gap-1 justify-between">
                <div class="font-mono text-[11px] break-all flex-1">{member.uri}</div>
                <button
                  :if={cc_agent_uri?(member.uri)}
                  type="button"
                  phx-click="switch_to_pty_for_agent"
                  phx-value-agent={member.uri}
                  title={"Open PTY for #{member.uri}"}
                  aria-label={"Open PTY for #{member.uri}"}
                  class="p-1 text-zinc-500 hover:text-zinc-900 dark:hover:text-zinc-100 hover:bg-zinc-100 dark:hover:bg-zinc-800 rounded shrink-0"
                >
                  <.icon name="terminal" size="xs" />
                </button>
              </div>
              <div class={member_status_class(member.online)}>
                {if member.online, do: "online", else: "offline"}
                <span :if={member.last_seen} class="text-zinc-400 dark:text-zinc-600 font-normal">
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

  # Phase 8b — `entity://agent/cc_<name>` is the cc-managed agent
  # convention (PR #149 flavor-prefix scheme).
  defp cc_agent_uri?("entity://agent/cc_" <> _), do: true
  defp cc_agent_uri?(_), do: false

  defp member_status_class(true), do: "text-[10px] text-emerald-600 dark:text-emerald-400 font-semibold"
  defp member_status_class(false), do: "text-[10px] text-zinc-400 dark:text-zinc-600"
end
