defmodule EsrPluginEcho.Application do
  @moduledoc """
  Echo plugin OTP application.

  ## Boot sequence

  1. Register `{Esr.Entity.Echo, :say} → Esr.Behavior.Echo` in the
     core `Esr.BehaviorRegistry`. Idempotent (re-runs on hot-reload
     overwrite cleanly).
  2. Start the per-Kind DynamicSupervisor so future instances can be
     spawned without restart of the whole plugin.
  3. Spawn the default `agent://echo` instance under that supervisor.

  ## Why a DynamicSupervisor

  Phase 1 only has one Echo instance, but the supervisor pattern is
  free here and makes Phase 2+ multi-instance spawning a one-liner
  (`DynamicSupervisor.start_child/2`). Direct `start_link` from
  Application.start/2 would force a plugin restart for each new
  instance.

  ## Why this app depends on `esr_core` via in_umbrella

  Plugin pattern: plugins live alongside `esr_core` in the umbrella
  but never reach into core internals — only via the public API
  (`Esr.BehaviorRegistry.register`, `Esr.Kind.Server.start_link`).
  This boundary is what lets future devs work on plugins without
  coordinating with the core team (the north-star feedback rule).
  """

  use Application

  @default_uri URI.parse("agent://echo")

  @impl true
  def start(_type, _args) do
    register_behaviors()

    children = [
      {DynamicSupervisor, name: __MODULE__.Supervisor, strategy: :one_for_one}
    ]

    case Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__) do
      {:ok, sup_pid} ->
        spawn_default_instance()
        {:ok, sup_pid}

      other ->
        other
    end
  end

  defp register_behaviors do
    :ok = Esr.BehaviorRegistry.register(Esr.Entity.Echo, :say, Esr.Behavior.Echo)
  end

  defp spawn_default_instance do
    spec = {Esr.Kind.Server, {Esr.Entity.Echo, %{uri: @default_uri}}}

    case DynamicSupervisor.start_child(__MODULE__.Supervisor, spec) do
      {:ok, _pid} ->
        :ok

      # Already started — happens if the supervisor restarted the plugin
      # but the prior instance was still alive (Phase 1 unlikely, kept
      # for hot-reload safety).
      {:error, {:already_started, _pid}} ->
        :ok
    end
  end

  @doc "URI of the default Echo instance spawned at boot."
  def default_uri, do: @default_uri
end
