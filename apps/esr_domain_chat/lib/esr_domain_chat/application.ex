defmodule EsrDomainChat.Application do
  @moduledoc """
  Chat plugin OTP application.

  ## Phase 2b boot sequence

  1. **Register Chat Behaviors per-Kind subset** (BehaviorRegistry) —
     before spawning any Kind so dispatch routes correctly on first
     message:

         Esr.Entity.Session  → :send | :join | :leave  → Esr.Behavior.Chat
         Esr.Entity.User     → :receive               → Esr.Behavior.Chat
         Esr.Entity.Agent    → :receive               → Esr.Behavior.Chat

     Per Decision P2-D2 K-path: one Behavior module, multiple Kinds
     each picking the subset of actions it consumes.

  2. **Children supervisor** —
     - `EsrDomainChat.AgentSupervisor` — DynamicSupervisor for Agent
       Kinds, 0 children at boot (Agents materialize when a bridge
       announces; 2c-step 1 wires the controller).
     - `Esr.Kind.Server` for `session://main` — the default Session.
     - `Esr.Kind.Server` for `user://admin` — Phase 2 promotes the
       admin User from a never-spawned stub to a live participant.

  3. **Post-boot admin join** — once Session and admin User are both
     alive, dispatch `session://main/behavior/chat/join` with
     `member: user://admin`. Using `:cast` so this is non-blocking;
     PendingDelivery absorbs the still-becoming-ready window (memory
     `feedback_let_it_crash_no_workarounds`: no defensive sleeps).

  ## Why post-boot dispatch (not Kind.Server.handle_continue)

  The /goal text suggested `handle_continue(:announce_ready)` as the
  dispatch site. Equivalent in effect for a single dispatch — but
  doing it from the Application keeps `Esr.Kind.Server` generic
  (it doesn't have to know about Chat or admin User's specific
  joining behavior). Application-level orchestration is the right
  layer for "after these processes are up, fire X" wiring.

  ## Why use Esr.Entity.User from esr_core (not move it here)

  `admin_uri/0` + `admin_caps/0` are widely referenced (snapshot tests,
  invocation tests, LV admin page, plugin Echo integration tests).
  Keeping User in esr_core means readers don't depend on this plugin.

  Per the same reasoning, `Esr.Entity.User.behaviors/0` returns `[]`
  — Chat is wired in via per-Kind `BehaviorRegistry.register` rather
  than via `behaviors/0`, so esr_core stays free of any
  `Esr.Behavior.Chat` reference.
  """

  use Application

  alias Esr.{BehaviorRegistry, Invocation, RoutingRegistry}
  alias Esr.Entity.{Agent, AgentTemplate, Session, SessionTemplate, User}
  alias Esr.Behavior.Chat
  alias EsrDomainChat.Routing.{MentionRouting, SessionRouting}

  @impl true
  def start(_type, _args) do
    :ok = register_chat_behaviors()
    :ok = declare_routing_tables()

    children = [
      {DynamicSupervisor, name: EsrDomainChat.AgentSupervisor, strategy: :one_for_one},
      {DynamicSupervisor, name: EsrDomainChat.SessionSupervisor, strategy: :one_for_one},
      # Phase 7 PR 37: supervisor for AgentTemplate Kinds. 0 children at
      # boot; templates materialize on admin create (LV or mix task) or
      # on snapshot restore at next reference.
      {DynamicSupervisor, name: EsrDomainChat.AgentTemplateSupervisor, strategy: :one_for_one},
      # Phase 7 PR 38: supervisor for SessionTemplate Kinds. Same shape
      # as AgentTemplateSupervisor — 0 children at boot, lazy spawn.
      {DynamicSupervisor, name: EsrDomainChat.SessionTemplateSupervisor, strategy: :one_for_one},
      kind_server_spec(:session_main, Session, Session.default_uri())
      # Phase 6 PR 2: admin User spawn moved to EsrDomainIdentity.Application
      # (User Kind belongs to identity domain). Chat's start callback below
      # still dispatches admin → join default Session.
    ]

    case Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__) do
      {:ok, sup_pid} ->
        :ok = admin_user_joins_default_session()
        :ok = EsrDomainChat.DefaultRules.bootstrap()

        # Phase 4c: chat plugin owns agent:// + session:// schemes.
        # user:// spawn fn moved to esr_domain_identity in Phase 6 PR 2.
        :ok = register_spawn_fns()

        # Phase 4-completion: register Template Classes this plugin provides.
        :ok = register_template_classes()

        # Phase 4c: load persisted Workspaces — runs here because chat is
        # the last domain app to boot, so all spawn fns are registered.
        # PR 12 closeout: replace with an explicit registry-ready gate.
        :ok = EsrDomainWorkspace.Application.boot_complete()

        {:ok, sup_pid}

      other ->
        other
    end
  end

  defp register_template_classes do
    :ok = Esr.TemplateRegistry.register(Esr.Template.GenericSession)
    :ok
  end

  defp register_spawn_fns do
    :ok =
      Esr.SpawnRegistry.register("agent", fn uri ->
        DynamicSupervisor.start_child(
          EsrDomainChat.AgentSupervisor,
          {Esr.Kind.Server, {Agent, %{uri: uri, initial_caps: MapSet.new()}}}
        )
      end)

    :ok =
      Esr.SpawnRegistry.register("session", fn uri ->
        DynamicSupervisor.start_child(
          EsrDomainChat.SessionSupervisor,
          {Esr.Kind.Server, {Session, %{uri: uri}}}
        )
      end)

    # Phase 7 PR 37: template:// scheme dispatches on host segment.
    # `template://agent/<name>` → AgentTemplate Kind.
    # `template://session/<name>@<hash>` → SessionTemplate Kind (PR 38).
    # The single spawn fn for the scheme switches on URI.host so
    # both Template Kinds share the same scheme namespace without
    # colliding on the registry.
    :ok =
      Esr.SpawnRegistry.register("template", fn uri ->
        case uri.host do
          "agent" ->
            DynamicSupervisor.start_child(
              EsrDomainChat.AgentTemplateSupervisor,
              {Esr.Kind.Server, {AgentTemplate, %{uri: uri}}}
            )

          "session" ->
            DynamicSupervisor.start_child(
              EsrDomainChat.SessionTemplateSupervisor,
              {Esr.Kind.Server, {SessionTemplate, %{uri: uri}}}
            )

          other ->
            {:error, {:unknown_template_host, other}}
        end
      end)

    # Phase 6 PR 2: user:// spawn fn moved to esr_domain_identity.

    :ok
  end

  defp register_chat_behaviors do
    :ok = BehaviorRegistry.register(Session, :send, Chat)
    :ok = BehaviorRegistry.register(Session, :join, Chat)
    :ok = BehaviorRegistry.register(Session, :leave, Chat)
    :ok = BehaviorRegistry.register(User, :receive, Chat)
    :ok = BehaviorRegistry.register(Agent, :receive, Chat)
    # Phase 6 PR 2: Identity behavior registration (list_caps / has_cap?)
    # moved to esr_domain_identity.Application — Identity is the identity
    # domain's concern, not chat's.
    :ok
  end

  # Phase 3a-step 4: declare 2 RoutingRegistry tables that this plugin
  # owns. MentionRouting is :duplicate (one matcher can fire on many
  # messages; one matcher → list of receivers; one rule per row).
  # SessionRouting is :unique (bridge_id → session_uri). Both declared
  # in this Application process — it owns writes.
  defp declare_routing_tables do
    :ok = RoutingRegistry.declare_table(MentionRouting, key_uniqueness: :duplicate)
    :ok = RoutingRegistry.declare_table(SessionRouting, key_uniqueness: :unique)
    :ok
  end

  # Phase 3d (#B1): accept extra_args map so callers can pass keys like
  # `:initial_caps` for Identity init_slice. Merges into `%{uri: uri}`.
  defp kind_server_spec(child_id, kind_module, uri, extra_args \\ %{}) do
    args = Map.merge(%{uri: uri}, extra_args)

    Supervisor.child_spec(
      {Esr.Kind.Server, {kind_module, args}},
      id: child_id
    )
  end

  defp admin_user_joins_default_session do
    admin_uri = User.admin_uri()
    session_uri = Session.default_uri()
    target = URI.new!("#{URI.to_string(session_uri)}/behavior/chat/join")

    _ =
      Invocation.dispatch(%Invocation{
        target: target,
        mode: :cast,
        args: %{member: admin_uri},
        ctx: %{
          caller: admin_uri,
          caps: User.admin_caps(),
          reply: :ignore
        }
      })

    :ok
  end
end
