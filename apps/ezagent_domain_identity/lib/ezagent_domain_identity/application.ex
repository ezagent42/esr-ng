defmodule EzagentDomainIdentity.Application do
  @moduledoc """
  Identity domain OTP application — Phase 6 PR 2.

  Owns:
  - `Ezagent.Entity.User` Kind boot (admin spawn, per-user spawn fn)
  - `Ezagent.Behavior.Identity` registration on User + Agent
  - `Ezagent.Users` SQLite provisioning (Phase 4-completion Spec 05)

  Does NOT own (Chat plugin owns those):
  - `Ezagent.Behavior.Chat` :receive registration on User/Agent
  - Session boot or admin-join-default-session

  ## Boot order

  Must start BEFORE any plugin that depends on User (chat, ezagent, ...).
  Umbrella resolves this via the `{:ezagent_domain_identity, in_umbrella: true}`
  dep in those apps' mix.exs.
  """

  use Application

  alias Ezagent.{BehaviorRegistry, SpawnRegistry}
  alias Ezagent.Entity.User
  alias Ezagent.Behavior.{Identity, ApiKeys}

  @impl true
  def start(_type, _args) do
    :ok = register_identity_behaviors()

    children = [
      {DynamicSupervisor, name: __MODULE__.UserSupervisor, strategy: :one_for_one},
      kind_server_spec(:user_admin, User, User.admin_uri(), %{
        initial_caps: User.admin_caps()
      })
    ]

    # PR #141 (SPEC v2): identity domain owns the User Kind, so it
    # registers an initial `entity://` spawn fn that handles `host =
    # "user"`. The chat plugin (which boots later — chat depends on
    # identity) OVERWRITES this registration with a combined fn that
    # additionally handles `host = "agent"` (PR #149 — snapshot /
    # template / flavor-prefix resolver; `Ezagent.AgentTypeRegistry`
    # was deleted). This layering keeps identity self-sufficient for
    # stacks that don't load chat (e.g. CLI-only test contexts).
    case Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__) do
      {:ok, sup_pid} ->
        :ok = register_user_only_entity_spawn_fn()
        {:ok, sup_pid}

      other ->
        other
    end
  end

  defp register_user_only_entity_spawn_fn do
    :ok =
      SpawnRegistry.register("entity", fn uri ->
        case uri.host do
          "user" ->
            DynamicSupervisor.start_child(
              __MODULE__.UserSupervisor,
              {Ezagent.Kind.Server, {User, %{uri: uri, initial_caps: MapSet.new()}}}
            )

          other ->
            {:error, {:no_entity_host_handler, other}}
        end
      end)

    :ok
  end

  defp register_identity_behaviors do
    for action <- Identity.actions() do
      :ok = BehaviorRegistry.register(User, action, Identity)
      # Agent identity-cap binding stays here too — Agent Kind belongs
      # to chat plugin but identity actions on it are an Identity
      # concern. Both apps load before plugins start dispatching, so
      # registering against Ezagent.Entity.Agent here is safe even though
      # Agent is defined in ezagent_domain_chat.
      :ok = BehaviorRegistry.register(Ezagent.Entity.Agent, action, Identity)
    end

    # PR #126: per-user API key storage (DeepSeek/OpenAI/etc.). Only
    # on User Kind — Agents don't own their own keys, they look up
    # the caller User's key via dispatch.
    for action <- ApiKeys.actions() do
      :ok = BehaviorRegistry.register(User, action, ApiKeys)
    end

    :ok
  end

  defp kind_server_spec(child_id, kind_module, uri, extra_args) do
    args = Map.merge(%{uri: uri}, extra_args)
    Supervisor.child_spec({Ezagent.Kind.Server, {kind_module, args}}, id: child_id)
  end
end
