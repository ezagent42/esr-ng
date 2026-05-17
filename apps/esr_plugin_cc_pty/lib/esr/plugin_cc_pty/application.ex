defmodule EsrPluginCcPty.Application do
  @moduledoc """
  CC PTY plugin Application.

  Phase 4-completion PR 8 simplified per Allen's call: this plugin
  spawns `claude` directly via PTY (erlexec). No native Elixir MCP
  server work — Phase 1 v1_prototype MCP bridge continues being used
  inside the spawned shell.

  ## Boot

  1. Register Template Class `Esr.PluginCcPty.Template` with
     `Esr.TemplateRegistry` so Workspaces can declare cc-pty agents
     via `session_templates`:

         "cc-architect" => %{
           "class" => "cc.pty",
           "agent_uri" => "agent://cc-architect",
           "cwd" => "/path/to/project"
         }

  2. Start `EsrPluginCcPty.PtyServerSupervisor` (DynamicSupervisor) —
     Template instantiate spawns one `PtyServer` per declared cc-pty.

  This is the **first non-chat plugin** to land — it exercises Phase 4
  plugin-isolation north star end-to-end (no esr_core / chat plugin
  changes needed to add this).
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {DynamicSupervisor, name: EsrPluginCcPty.PtyServerSupervisor, strategy: :one_for_one}
    ]

    case Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__) do
      {:ok, sup_pid} ->
        :ok = register_template_class()
        :ok = register_pty_input_kind()

        # Boot-ordering fix: chat plugin's Application.start calls
        # Esr.Workspace.Loader.load_all/0 BEFORE this plugin starts —
        # at that point cc.pty Template Class isn't registered yet, so
        # any Workspace declaring `"class" => "cc.pty"` gets logged
        # "no Template Class registered" + skipped. Re-run Loader now
        # that we're registered to pick up those Workspaces.
        _ = Esr.Workspace.Loader.load_all()

        {:ok, sup_pid}

      other ->
        other
    end
  end

  defp register_template_class do
    :ok = Esr.TemplateRegistry.register(Esr.PluginCcPty.Template)
    :ok
  end

  # Phase 5 PR 4: synthetic PtyInput Kind + Behavior.Pty for xterm.js
  # LV's input dispatch path. Mirrors RoutingAdmin pattern (Decision #125).
  defp register_pty_input_kind do
    alias Esr.BehaviorRegistry
    alias Esr.Behavior.Pty, as: PtyB
    alias Esr.Entity.PtyInput, as: PtyK

    Enum.each(PtyB.actions(), fn action ->
      :ok = BehaviorRegistry.register(PtyK, action, PtyB)
    end)

    uri = PtyK.default_uri()

    case Esr.KindRegistry.lookup(uri) do
      {:ok, _pid} ->
        :ok

      :error ->
        case DynamicSupervisor.start_child(
               Esr.Workspace.Supervisor,
               {Esr.Kind.Server, {PtyK, %{uri: uri}}}
             ) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          err -> err
        end
    end
  end
end
