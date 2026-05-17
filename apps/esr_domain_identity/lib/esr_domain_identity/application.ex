defmodule EsrDomainIdentity.Application do
  @moduledoc """
  Identity domain OTP application — Phase 6 PR 2.

  Owns:
  - `Esr.Entity.User` Kind boot (admin spawn, per-user spawn fn)
  - `Esr.Behavior.Identity` registration on User + Agent
  - `Esr.Users` SQLite provisioning (Phase 4-completion Spec 05)

  Does NOT own (Chat plugin owns those):
  - `Esr.Behavior.Chat` :receive registration on User/Agent
  - Session boot or admin-join-default-session

  ## Boot order

  Must start BEFORE any plugin that depends on User (chat, ezagent, ...).
  Umbrella resolves this via the `{:esr_domain_identity, in_umbrella: true}`
  dep in those apps' mix.exs.
  """

  use Application

  alias Esr.{BehaviorRegistry, SpawnRegistry}
  alias Esr.Entity.User
  alias Esr.Behavior.Identity

  @impl true
  def start(_type, _args) do
    :ok = register_identity_behaviors()

    children = [
      {DynamicSupervisor, name: __MODULE__.UserSupervisor, strategy: :one_for_one},
      kind_server_spec(:user_admin, User, User.admin_uri(), %{
        initial_caps: User.admin_caps()
      })
    ]

    case Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__) do
      {:ok, sup_pid} ->
        :ok = register_user_spawn_fn()
        {:ok, sup_pid}

      other ->
        other
    end
  end

  defp register_identity_behaviors do
    :ok = BehaviorRegistry.register(User, :list_caps, Identity)
    :ok = BehaviorRegistry.register(User, :has_cap?, Identity)
    # Agent identity-cap binding stays here too — Agent Kind belongs to
    # chat plugin but :list_caps/:has_cap? on it is an Identity concern.
    # Both apps load before plugins start dispatching, so registering
    # against Esr.Entity.Agent here is safe even though Agent is defined
    # in esr_domain_chat (the atom resolves; the actual entity module
    # only needs to exist before someone *invokes* it, not at register
    # time).
    :ok = BehaviorRegistry.register(Esr.Entity.Agent, :list_caps, Identity)
    :ok = BehaviorRegistry.register(Esr.Entity.Agent, :has_cap?, Identity)
    :ok
  end

  defp register_user_spawn_fn do
    :ok =
      SpawnRegistry.register("user", fn uri ->
        DynamicSupervisor.start_child(
          __MODULE__.UserSupervisor,
          {Esr.Kind.Server, {User, %{uri: uri, initial_caps: MapSet.new()}}}
        )
      end)

    :ok
  end

  defp kind_server_spec(child_id, kind_module, uri, extra_args) do
    args = Map.merge(%{uri: uri}, extra_args)
    Supervisor.child_spec({Esr.Kind.Server, {kind_module, args}}, id: child_id)
  end
end
