defmodule EsrDomainWorkspace.Application do
  @moduledoc """
  Workspace domain OTP application — Phase 6 PR 2.

  Owns:
  - `Esr.Behavior.Workspace` registration on `Esr.Entity.Workspace`
  - `Esr.Workspace.Supervisor` DynamicSupervisor for `workspace://*` Kinds
  - `Esr.Workspace.Loader.load_all/0` invocation (deferred to last
    boot site — see notes)

  ## load_all timing

  Loader needs every plugin's spawn fn already registered (e.g.
  `agent`, `session`, `user`, `pty` schemes). Those registrations
  happen at each plugin's Application.start. The umbrella's child app
  start order is alphabetical, so esr_domain_workspace starts before
  most plugins.

  Solution: domain_workspace does NOT call load_all here. Instead it
  exposes `EsrDomainWorkspace.boot_complete/0` which the LAST app to
  boot (currently esr_domain_chat, post-PR-3 esr_plugin_ezagent)
  invokes after all spawn fns are registered. PR 3+ will move this
  call site to an explicit "registry-ready" gate.
  """

  use Application

  alias Esr.BehaviorRegistry
  alias Esr.Behavior.Workspace, as: WB
  alias Esr.Entity.Workspace, as: WK

  @impl true
  def start(_type, _args) do
    :ok = register_workspace_behavior()

    children = [
      {DynamicSupervisor, name: Esr.Workspace.Supervisor, strategy: :one_for_one}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__)
  end

  defp register_workspace_behavior do
    Enum.each(WB.actions(), fn action ->
      :ok = BehaviorRegistry.register(WK, action, WB)
    end)

    :ok
  end

  @doc """
  Called by the last-booting app once all spawn fns are registered.
  Idempotent — multiple callers OK (Loader handles "already spawned").
  """
  def boot_complete do
    _ = Esr.Workspace.Loader.load_all()
    :ok
  end
end
