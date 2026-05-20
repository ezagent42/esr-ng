defmodule EzagentPluginCc.Views.PtyView do
  @moduledoc """
  Phase 8b — Session view: xterm.js terminal for a `cc_*` agent member.

  Renders the same PtyTerminal JS hook the (now-retired) standalone
  `/identities/agents/:uri/terminal` page used. The active agent
  URI is owned by the wrapping admin_live as `@active_pty_agent_uri`
  (set when the operator clicks a Members panel PTY button, or when
  the view-switcher opens with a default cc member).

  Applies only to sessions that have at least one `entity://agent/cc_*`
  member — peeked via `:sys.get_state` on the Session Kind with a
  short timeout + try/catch so a slow session doesn't block the LV
  render. Returning false is the safe failure mode (Terminal button
  just doesn't show up).

  Registered by `EzagentPluginCc.Application.start/2`.
  """

  @behaviour Ezagent.UI.SessionView
  use Phoenix.Component

  @impl true
  def id, do: :pty

  @impl true
  def label, do: "Terminal"

  @impl true
  def icon, do: "terminal"

  @impl true
  def applies_to?(%URI{} = session_uri) do
    case Ezagent.KindRegistry.lookup(session_uri) do
      {:ok, pid} ->
        try do
          %{state: %{chat: slice}} = :sys.get_state(pid, 200)

          slice.members
          |> Map.keys()
          |> Enum.any?(&cc_agent_uri?/1)
        catch
          _, _ -> false
        end

      :error ->
        false
    end
  end

  def applies_to?(_), do: false

  # `entity://agent/cc_<name>` — the `cc_` prefix is the agent-flavor
  # marker (per PR #149 entity-agnostic reflection: flavor is a free-form
  # prefix on the URI's name segment). Any agent whose name begins with
  # `cc_` is a cc-managed agent.
  defp cc_agent_uri?(%URI{scheme: "entity", host: "agent", path: "/" <> name})
       when is_binary(name) do
    String.starts_with?(name, "cc_")
  end

  defp cc_agent_uri?(_), do: false

  @impl true
  def render(assigns) do
    assigns = assign_new(assigns, :active_pty_agent_uri, fn -> nil end)

    ~H"""
    <div class="flex-1 flex flex-col bg-black text-zinc-200 min-h-0">
      <div class="px-3 py-1 text-[11px] text-zinc-400 bg-zinc-900 border-b border-zinc-800 shrink-0">
        Terminal —
        <span class="font-mono">{@active_pty_agent_uri || "select a cc agent from Members panel"}</span>
      </div>

      <div :if={is_nil(@active_pty_agent_uri)} class="flex-1 flex items-center justify-center text-zinc-500 text-xs">
        Click the 🖥️ icon next to a cc agent in the Members panel to attach.
      </div>

      <div
        :if={@active_pty_agent_uri}
        id={pty_dom_id(@active_pty_agent_uri)}
        phx-hook="PtyTerminal"
        phx-update="ignore"
        class="flex-1 min-h-0"
      ></div>
    </div>
    """
  end

  # Unique DOM id per agent URI so switching attached agents recreates
  # the xterm instance instead of trying to re-mount onto a stale buffer.
  defp pty_dom_id(uri_str) when is_binary(uri_str),
    do: "pty-terminal-" <> Base.url_encode64(uri_str, padding: false)

  defp pty_dom_id(%URI{} = uri),
    do: pty_dom_id(URI.to_string(uri))

  defp pty_dom_id(_), do: "pty-terminal-none"
end
