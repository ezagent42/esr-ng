defmodule EsrPluginChat.Application do
  @moduledoc """
  Chat plugin OTP application.

  ## Phase 2b-step 1 scope (this commit)

  Boot wiring for the three Chat-participating Kinds:

  1. `EsrPluginChat.AgentSupervisor` — DynamicSupervisor for Agent
     Kinds. Starts with **zero children**; Agent Kinds spawn when a
     bridge announces (2c-step 1 wires the controller).
  2. `Esr.Kind.Server` for `session://main` — the default Session.
  3. `Esr.Kind.Server` for `user://admin` — Phase 2 promotes the
     admin User from "Phase 1 stub callbacks, never spawned" to a
     live Kind that can be a chat participant.

  Per-Kind BehaviorRegistry registration + Chat invoke bodies arrive
  in 2b-step 2. This step only stands up the processes.

  ## Boot order

  `esr_core` boots first (Repo / Registry / EtsOwner / BehaviorRegistry
  table / PubSub) — `extra_applications` in mix.exs declares the dep.
  When `start/2` runs here, `KindRegistry` + `ReadyGate` +
  `PendingDelivery` are all live, so the Kind.Server lifecycle
  (register → ready → flush pending) works.

  ## Why distinct child ids

  Session and admin User both use `Esr.Kind.Server` as their server
  module. Default `child_spec/1` derives id from the module — they'd
  collide. Each spec gets an explicit `id:` keyed to its URI so the
  Supervisor can track them independently and restart per-instance.

  ## Why use Esr.Entity.User from esr_core (not move it here)

  The admin User module + its `admin_uri/0` / `admin_caps/0` constants
  are widely referenced (snapshot tests, invocation tests, LV admin
  page, plugin Echo integration tests). Moving it to `esr_plugin_chat`
  would force every reader to dep on this plugin — wrong direction.
  We keep User in `esr_core` (data + bootstrap constants) and spawn
  the instance here (lifecycle is plugin-driven, per the
  plugin-isolation north-star).

  Per the same reasoning, `Esr.Entity.User.behaviors/0` returns `[]`
  — Chat is wired in via per-Kind `BehaviorRegistry.register`
  (2b-step 2) rather than via `behaviors/0`, so esr_core doesn't have
  to reference `Esr.Behavior.Chat`.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {DynamicSupervisor, name: EsrPluginChat.AgentSupervisor, strategy: :one_for_one},
      kind_server_spec(:session_main, Esr.Entity.Session, Esr.Entity.Session.default_uri()),
      kind_server_spec(:user_admin, Esr.Entity.User, Esr.Entity.User.admin_uri())
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__)
  end

  defp kind_server_spec(child_id, kind_module, uri) do
    Supervisor.child_spec(
      {Esr.Kind.Server, {kind_module, %{uri: uri}}},
      id: child_id
    )
  end
end
