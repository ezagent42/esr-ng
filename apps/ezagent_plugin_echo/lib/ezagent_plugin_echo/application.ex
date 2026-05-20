defmodule EzagentPluginEcho.Application do
  @moduledoc """
  Echo plugin OTP application.

  ## Boot sequence

  1. Register `{Ezagent.Entity.Echo, :say} → Ezagent.Behavior.Echo` in the
     core `Ezagent.BehaviorRegistry`. Idempotent (re-runs on hot-reload
     overwrite cleanly).
  2. Start the per-Kind DynamicSupervisor so future instances can be
     spawned without restart of the whole plugin.
  3. Spawn the default `entity://agent/echo_default` instance (PR #141
     SPEC v2 — agent flavor lives in the name prefix) under that
     supervisor.

  ## PR #149 (SPEC v2 §5.14)

  `Ezagent.AgentTypeRegistry` was deleted. This plugin no longer
  registers an `"echo"` flavor → spawn fn pair. The default Echo
  instance still spawns under this plugin's own `Supervisor` at boot
  (direct `DynamicSupervisor.start_child/2`); the chat plugin's
  `entity://` SpawnRegistry fn resolves the `echo` flavor for
  CLI-driven / test-time spawns via its three-step lookup (snapshot →
  template → flavor-prefix).

  ## Why a DynamicSupervisor

  Phase 1 only has one Echo instance, but the supervisor pattern is
  free here and makes Phase 2+ multi-instance spawning a one-liner
  (`DynamicSupervisor.start_child/2`). Direct `start_link` from
  Application.start/2 would force a plugin restart for each new
  instance.

  ## Why this app depends on `ezagent_core` via in_umbrella

  Plugin pattern: plugins live alongside `ezagent_core` in the umbrella
  but never reach into core internals — only via the public API
  (`Ezagent.BehaviorRegistry.register`, `Ezagent.Kind.Server.start_link`).
  This boundary is what lets future devs work on plugins without
  coordinating with the core team (the north-star feedback rule).
  """

  use Application

  # PR #141 (SPEC v2): `agent://` scheme deleted; merged into `entity://`.
  # Agent flavor moves to free-form name prefix (SPEC §5.14):
  # Echo's default instance is `entity://agent/echo_default`.
  @default_uri URI.parse("entity://agent/echo_default")

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
    # `:say` is the historical programmatic-invoke action (Phase 1
    # contract). `:receive` is the fan-out hook — Session's chat.send
    # dispatches `chat.receive` to every Echo agent in members; without
    # this registration, that dispatch returns `:not_registered` and
    # the echo agent silently drops every chat msg (the regression
    # Allen flagged 2026-05-20).
    :ok = Ezagent.BehaviorRegistry.register(Ezagent.Entity.Echo, :say, Ezagent.Behavior.Echo)
    :ok = Ezagent.BehaviorRegistry.register(Ezagent.Entity.Echo, :receive, Ezagent.Behavior.Echo)
  end

  defp spawn_default_instance do
    spec = {Ezagent.Kind.Server, {Ezagent.Entity.Echo, %{uri: @default_uri}}}

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
