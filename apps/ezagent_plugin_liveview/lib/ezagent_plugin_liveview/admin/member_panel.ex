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
  attr :floating_agents, :list, default: []

  # Username & Auth UI Task 1 (PR-O) — `%{uri_str => display_name}`
  # batch-resolved by admin_live via `Ezagent.EntityPresenter.display_many/1`.
  # Empty map = fall back to URI path segment for each member.
  attr :display_map, :map, default: %{}

  def member_panel(assigns) do
    ~H"""
    <aside id="session-members" class="p-3 text-zinc-800 dark:text-zinc-200">
      <h3 class="text-[10px] uppercase tracking-wide text-zinc-500 mb-2">Members</h3>
      <%!-- Phase 8c follow-up (Allen 2026-05-20) — the prior copy
            "(No members — Chat plugin failed to start?)" blamed the
            chat plugin for a normal cold-start state. Empty here just
            means the session has no joined members yet — invite an
            agent via the picker below. AdminLive.ensure_main_session/2
            guarantees the session itself exists before we render. --%>
      <p :if={@members == []} id="session-members-empty" class="text-xs text-zinc-500">
        No members yet. Invite an agent from the picker below.
      </p>
      <table :if={@members != []} id="session-members-table" class="w-full text-xs">
        <tbody>
          <tr :for={member <- @members} class="border-b border-zinc-100 dark:border-zinc-900">
            <td class="py-1.5 align-top">
              <div class="flex items-start gap-1 justify-between">
                <div class="flex-1 min-w-0">
                  <%!-- Display name primary, URI mono subtitle. --%>
                  <div class="text-xs font-medium text-zinc-800 dark:text-zinc-200 truncate">
                    {display_for(member.uri, @display_map)}
                  </div>
                  <div class="font-mono text-[10px] text-zinc-400 dark:text-zinc-600 break-all">{member.uri}</div>
                </div>
                <button
                  :if={cc_agent_uri?(member.uri)}
                  type="button"
                  phx-click="switch_to_pty_for_agent"
                  phx-value-agent={member.uri}
                  title={"Open PTY for #{display_for(member.uri, @display_map)}"}
                  aria-label={"Open PTY for #{display_for(member.uri, @display_map)}"}
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

      <%!-- Phase 8c PR-E (Allen 2026-05-20) — restore "Floating agents"
            picker that pre-Phase-8b sessions_sidebar provided. Lets
            an operator add any agent in KindRegistry that isn't yet
            a member of any session to the current session. --%>
      <div :if={@floating_agents != []} class="mt-4 pt-3 border-t border-zinc-200 dark:border-zinc-800">
        <h3 class="text-[10px] uppercase tracking-wide text-zinc-500 mb-2">Floating agents</h3>
        <form phx-change="add_floating_agent" class="contents">
          <select
            name="agent_uri"
            id="floating-agents-picker"
            class="w-full text-[11px] px-2 py-1 border border-zinc-300 dark:border-zinc-700 rounded bg-white dark:bg-zinc-900 text-zinc-800 dark:text-zinc-200"
          >
            <option value="">— add to session…</option>
            <option :for={uri <- @floating_agents} value={uri}>{display_for(uri, @display_map)}</option>
          </select>
        </form>
      </div>
    </aside>
    """
  end

  # Username & Auth UI Task 1 — falls back to URI path segment when
  # the batch map is missing (defensive for pre-PR call sites).
  defp display_for(uri_str, %{} = display_map) do
    case Map.get(display_map, uri_str) do
      name when is_binary(name) and name != "" -> name
      _ -> Ezagent.EntityPresenter.display(uri_str)
    end
  end

  # Phase 8b — `entity://agent/cc_<name>` is the cc-managed agent
  # convention (PR #149 flavor-prefix scheme).
  defp cc_agent_uri?("entity://agent/cc_" <> _), do: true
  defp cc_agent_uri?(_), do: false

  defp member_status_class(true), do: "text-[10px] text-emerald-600 dark:text-emerald-400 font-semibold"
  defp member_status_class(false), do: "text-[10px] text-zinc-400 dark:text-zinc-600"
end
