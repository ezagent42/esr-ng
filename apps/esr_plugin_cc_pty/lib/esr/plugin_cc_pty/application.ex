defmodule EsrPluginCcPty.Application do
  @moduledoc """
  CC PTY plugin Application.

  Phase 4-completion PR 8 simplified per Allen's call: this plugin
  **wraps `bash scripts/cc-bridge-attach.sh` via PTY** (erlexec). No
  native Elixir MCP server work — Phase 1 v1_prototype MCP bridge
  continues being used inside the spawned shell.

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
        {:ok, sup_pid}

      other ->
        other
    end
  end

  defp register_template_class do
    :ok = Esr.TemplateRegistry.register(Esr.PluginCcPty.Template)
    :ok
  end
end
