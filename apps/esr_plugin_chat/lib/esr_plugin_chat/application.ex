defmodule EsrPluginChat.Application do
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
     - `EsrPluginChat.AgentSupervisor` — DynamicSupervisor for Agent
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
  alias Esr.Entity.{Agent, Session, User}
  alias Esr.Behavior.Chat
  alias EsrPluginChat.Routing.{MentionRouting, SessionRouting}

  @impl true
  def start(_type, _args) do
    :ok = register_chat_behaviors()
    :ok = declare_routing_tables()

    children = [
      {DynamicSupervisor, name: EsrPluginChat.AgentSupervisor, strategy: :one_for_one},
      kind_server_spec(:session_main, Session, Session.default_uri()),
      kind_server_spec(:user_admin, User, User.admin_uri())
    ]

    case Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__) do
      {:ok, sup_pid} ->
        :ok = admin_user_joins_default_session()
        :ok = EsrPluginChat.DefaultRules.bootstrap()
        {:ok, sup_pid}

      other ->
        other
    end
  end

  defp register_chat_behaviors do
    :ok = BehaviorRegistry.register(Session, :send, Chat)
    :ok = BehaviorRegistry.register(Session, :join, Chat)
    :ok = BehaviorRegistry.register(Session, :leave, Chat)
    :ok = BehaviorRegistry.register(User, :receive, Chat)
    :ok = BehaviorRegistry.register(Agent, :receive, Chat)
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

  defp kind_server_spec(child_id, kind_module, uri) do
    Supervisor.child_spec(
      {Esr.Kind.Server, {kind_module, %{uri: uri}}},
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
