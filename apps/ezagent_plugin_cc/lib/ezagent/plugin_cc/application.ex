defmodule EzagentPluginCc.Application do
  @moduledoc """
  CC plugin Application — the unified Claude Code agent plugin
  (Allen 2026-05-19: merged from the previous `ezagent_plugin_cc_pty`
  + `ezagent_plugin_cc_channel` apps; both predecessors deleted).

  Responsibilities:

  - Run PTY-managed `claude` processes via erlexec (`PtyServer`)
  - Host the v2 Phoenix.Channel WS bridge at `/cc_socket`
    (`Socket` + `Channel` + `BridgeRegistry`)
  - Mint + persist per-instance connect tokens (`TokenStore`)
  - Write the `mcp.json` Claude reads for the WS bridge sidecar
    (`McpConfigWriter`)
  - Register Template Classes: `cc.pty` (the agent), `cc.channel_instance`
    (legacy / back-compat — its work is folded into `cc.pty` now)

  ## Why merged

  Pre-merge the operator had to add TWO templates per CC agent —
  one `cc.pty` (spawns the PTY) and one `cc.channel_instance` (mints
  the token + makes BridgeRegistry happy). They were always added
  together, deleted together. The split was originally justified
  by "maybe we'll reuse cc_channel without cc_pty someday" — but
  any such reuse can happen at the code layer (drop into this
  plugin, call our public functions). No need for a plugin
  boundary.

  Now: ONE template (`cc.pty`), ONE plugin, full functionality.

  ## Boot order

  1. Init BridgeRegistry (ETS table for agent_uri → Channel pid)
  2. Start the per-PtyServer DynamicSupervisor + the synthetic
     PtyInput Kind that hosts the `Behavior.Pty.write` action
     (xterm.js input dispatch target)
  3. Register Template Classes (`cc.pty`, `cc.channel_instance`)
  4. Re-run `Workspace.Loader.load_all/0` to instantiate any
     CC templates that were skipped during boot before this
     plugin was up
  """

  use Application

  alias EzagentPluginCc.BridgeRegistry

  @impl true
  def start(_type, _args) do
    :ok = BridgeRegistry.init()

    children = [
      {DynamicSupervisor, name: EzagentPluginCc.PtyServerSupervisor, strategy: :one_for_one}
    ]

    case Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__) do
      {:ok, sup_pid} ->
        :ok = register_template_classes()
        :ok = register_pty_input_kind()

        # Boot-ordering fix: chat plugin's Application.start calls
        # Ezagent.Workspace.Loader.load_all/0 BEFORE this plugin
        # starts. Re-run here so Workspaces declaring our Template
        # Classes get instantiated.
        _ = Ezagent.Workspace.Loader.load_all()

        {:ok, sup_pid}

      other ->
        other
    end
  end

  defp register_template_classes do
    :ok = Ezagent.TemplateRegistry.register(Ezagent.PluginCc.Template)
    :ok = Ezagent.TemplateRegistry.register(Ezagent.Template.CcChannelInstance)
    :ok
  end

  # Phase 5 PR 4: synthetic PtyInput Kind + Behavior.Pty for xterm.js
  # LV's input dispatch path. Mirrors RoutingAdmin pattern (Decision #125).
  defp register_pty_input_kind do
    alias Ezagent.BehaviorRegistry
    alias Ezagent.Behavior.Pty, as: PtyB
    alias Ezagent.Entity.PtyInput, as: PtyK

    Enum.each(PtyB.actions(), fn action ->
      :ok = BehaviorRegistry.register(PtyK, action, PtyB)
    end)

    uri = PtyK.default_uri()

    case Ezagent.KindRegistry.lookup(uri) do
      {:ok, _pid} ->
        :ok

      :error ->
        case DynamicSupervisor.start_child(
               Ezagent.Workspace.Supervisor,
               {Ezagent.Kind.Server, {PtyK, %{uri: uri}}}
             ) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          err -> err
        end
    end
  end
end
