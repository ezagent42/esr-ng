defmodule EzagentDomainChat.Application do
  @moduledoc """
  Chat plugin OTP application.

  ## Phase 2b boot sequence

  1. **Register Chat Behaviors per-Kind subset** (BehaviorRegistry) —
     before spawning any Kind so dispatch routes correctly on first
     message:

         Ezagent.Entity.Session  → :send | :join | :leave  → Ezagent.Behavior.Chat
         Ezagent.Entity.User     → :receive               → Ezagent.Behavior.Chat
         Ezagent.Entity.Agent    → :receive               → Ezagent.Behavior.Chat

     PR #141 (SPEC v2): User+Agent merged into the `entity://` scheme;
     `Kind` modules are unchanged (`Ezagent.Entity.User` /
     `Ezagent.Entity.Agent` keep their existing names — the URI shape
     changed, not the OTP topology).

     Per Decision P2-D2 K-path: one Behavior module, multiple Kinds
     each picking the subset of actions it consumes.

  2. **Children supervisor** —
     - `EzagentDomainChat.AgentSupervisor` — DynamicSupervisor for Agent
       Kinds, 0 children at boot (Agents materialize when a bridge
       announces; 2c-step 1 wires the controller).
     - `Ezagent.Kind.Server` for `session://default/main` — the default Session.
     - `Ezagent.Kind.Server` for `entity://user/admin` — Phase 2 promotes the
       admin User from a never-spawned stub to a live participant.

  3. **Post-boot admin join** — once Session and admin User are both
     alive, dispatch `session://main?action=chat.join` with
     `member: entity://user/admin`. Using `:cast` so this is non-blocking;
     PendingDelivery absorbs the still-becoming-ready window (memory
     `feedback_let_it_crash_no_workarounds`: no defensive sleeps).

  ## Why post-boot dispatch (not Kind.Server.handle_continue)

  The /goal text suggested `handle_continue(:announce_ready)` as the
  dispatch site. Equivalent in effect for a single dispatch — but
  doing it from the Application keeps `Ezagent.Kind.Server` generic
  (it doesn't have to know about Chat or admin User's specific
  joining behavior). Application-level orchestration is the right
  layer for "after these processes are up, fire X" wiring.

  ## Why use Ezagent.Entity.User from ezagent_core (not move it here)

  `admin_uri/0` + `admin_caps/0` are widely referenced (snapshot tests,
  invocation tests, LV admin page, plugin Echo integration tests).
  Keeping User in ezagent_core means readers don't depend on this plugin.

  Per the same reasoning, `Ezagent.Entity.User.behaviors/0` returns `[]`
  — Chat is wired in via per-Kind `BehaviorRegistry.register` rather
  than via `behaviors/0`, so ezagent_core stays free of any
  `Ezagent.Behavior.Chat` reference.
  """

  use Application

  alias Ezagent.{BehaviorRegistry, Invocation, RoutingRegistry}
  alias Ezagent.Entity.{Agent, AgentTemplate, Session, SessionTemplate, User}
  alias Ezagent.Behavior.Chat
  alias EzagentDomainChat.Routing.{MentionRouting, SessionRouting}

  @impl true
  def start(_type, _args) do
    :ok = register_chat_behaviors()
    :ok = declare_routing_tables()

    children = [
      {DynamicSupervisor, name: EzagentDomainChat.AgentSupervisor, strategy: :one_for_one},
      {DynamicSupervisor, name: EzagentDomainChat.SessionSupervisor, strategy: :one_for_one},
      # Phase 7 PR 37: supervisor for AgentTemplate Kinds. 0 children at
      # boot; templates materialize on admin create (LV or mix task) or
      # on snapshot restore at next reference.
      {DynamicSupervisor, name: EzagentDomainChat.AgentTemplateSupervisor, strategy: :one_for_one},
      # Phase 7 PR 38: supervisor for SessionTemplate Kinds. Same shape
      # as AgentTemplateSupervisor — 0 children at boot, lazy spawn.
      {DynamicSupervisor, name: EzagentDomainChat.SessionTemplateSupervisor, strategy: :one_for_one},
      kind_server_spec(:session_main, Session, Session.default_uri())
      # Phase 6 PR 2: admin User spawn moved to EzagentDomainIdentity.Application
      # (User Kind belongs to identity domain). Chat's start callback below
      # still dispatches admin → join default Session.
    ]

    case Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__) do
      {:ok, sup_pid} ->
        :ok = bind_default_session_to_default_workspace()
        :ok = admin_user_joins_default_session()
        :ok = EzagentDomainChat.DefaultRules.bootstrap()

        # PR #141 (SPEC v2): chat plugin now owns the unified `entity://`
        # scheme + `session://`. The identity domain's user:// spawn fn
        # is removed; identity's UserSupervisor is referenced by name
        # from inside the entity:// dispatch in `register_spawn_fns/0`.
        :ok = register_spawn_fns()

        # Phase 4-completion: register Template Classes this plugin provides.
        :ok = register_template_classes()

        # Phase 4c: load persisted Workspaces — runs here because chat is
        # the last domain app to boot, so all spawn fns are registered.
        # PR 12 closeout: replace with an explicit registry-ready gate.
        :ok = EzagentDomainWorkspace.Application.boot_complete()

        # Phase 7 PR 45: install the cc-orchestrator AgentTemplate seed
        # so SessionTemplate-instantiation paths (PR 41 Generator) can
        # reference `template://agent/cc-orchestrator` without operator
        # setup. Idempotent: re-install on existing template is a no-op.
        :ok = seed_cc_orchestrator_template()

        {:ok, sup_pid}

      other ->
        other
    end
  end

  defp register_template_classes do
    :ok = Ezagent.TemplateRegistry.register(Ezagent.Template.GenericSession)
    :ok
  end

  # Phase 7 PR 45 — seed cc-orchestrator AgentTemplate at boot.
  #
  # The cc-orchestrator is the LLM-driven session-internal manager
  # (Decision D7-1, #136). Every SessionTemplate's
  # `orchestrator_template_uri` field defaults to
  # `template://agent/cc-orchestrator` — so the template must exist
  # by the time the Generator (PR 41) tries to spawn an orchestrator
  # instance. This boot-time seed makes that resolution work
  # out-of-the-box in dev / single-host deployments.
  #
  # Slice values use placeholder defaults pointing at the operator's
  # current `~/.claude/` — production multi-tenant deployments will
  # configure per-template `claude_config_dir` to isolate sandboxes
  # (D7-2 AgentTemplate slice fields). macOS Keychain caveat applies
  # — multi-orchestrator on one mac shares Keychain credentials; use
  # `api_key_helper` or separate OS users (skill anti-pattern + runbook).
  #
  # Spawn semantics: SpawnRegistry returns `{:error, {:already_started, _}}`
  # if the Kind is already alive (snapshot restore on subsequent
  # boots); this fn treats that as success per the boot-seed
  # idempotency convention.
  defp seed_cc_orchestrator_template do
    uri = URI.parse("template://agent/cc-orchestrator")

    case Ezagent.SpawnRegistry.spawn(uri) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} ->
        require Logger
        Logger.warning(
          "Failed to seed cc-orchestrator template at boot: #{inspect(reason)}; " <>
            "orchestrator-style SessionTemplate instantiation will fail until manually created"
        )
        :ok
    end
  end

  defp register_spawn_fns do
    # PR #141 (SPEC v2): `user://` + `agent://` schemes are deleted;
    # both merge into `entity://`. The chat plugin owns the unified
    # `entity://` spawn fn — dispatch by `uri.host`:
    #
    # - `entity://user/<name>` → spawn `Ezagent.Entity.User` under
    #   `EzagentDomainIdentity.Application.UserSupervisor` (identity
    #   domain owns User Kind; chat references its supervisor by
    #   module name per task spec).
    # - `entity://agent/<flavor>_<name>` → resolve the backing
    #   `kind_module` via `lookup_kind_module_for_agent/1` (snapshot →
    #   workspace-template → flavor-prefix fallback) and spawn under
    #   `EzagentDomainChat.AgentSupervisor`.
    #
    # PR #149 (SPEC v2 §5.14): `Ezagent.AgentTypeRegistry` deleted.
    # Per-flavor lookup table replaced by snapshot-first /
    # template-second / prefix-fallback resolution. Plugins no longer
    # register flavor → spawn fn pairs; Template Class registration is
    # the declarative channel for new agent flavors.
    :ok =
      Ezagent.SpawnRegistry.register("entity", fn uri ->
        case uri.host do
          "user" ->
            DynamicSupervisor.start_child(
              EzagentDomainIdentity.Application.UserSupervisor,
              {Ezagent.Kind.Server, {User, %{uri: uri, initial_caps: MapSet.new()}}}
            )

          "agent" ->
            spawn_agent(uri)

          other ->
            {:error, {:unknown_entity_host, other}}
        end
      end)

    :ok =
      Ezagent.SpawnRegistry.register("session", fn uri ->
        DynamicSupervisor.start_child(
          EzagentDomainChat.SessionSupervisor,
          {Ezagent.Kind.Server, {Session, %{uri: uri}}}
        )
      end)

    # Phase 7 PR 37: template:// scheme dispatches on host segment.
    # `template://agent/<name>` → AgentTemplate Kind.
    # `template://session/<name>@<hash>` → SessionTemplate Kind (PR 38).
    # The single spawn fn for the scheme switches on URI.host so
    # both Template Kinds share the same scheme namespace without
    # colliding on the registry.
    :ok =
      Ezagent.SpawnRegistry.register("template", fn uri ->
        case uri.host do
          "agent" ->
            DynamicSupervisor.start_child(
              EzagentDomainChat.AgentTemplateSupervisor,
              {Ezagent.Kind.Server, {AgentTemplate, %{uri: uri}}}
            )

          "session" ->
            DynamicSupervisor.start_child(
              EzagentDomainChat.SessionTemplateSupervisor,
              {Ezagent.Kind.Server, {SessionTemplate, %{uri: uri}}}
            )

          other ->
            {:error, {:unknown_template_host, other}}
        end
      end)

    :ok
  end

  defp register_chat_behaviors do
    :ok = BehaviorRegistry.register(Session, :send, Chat)
    :ok = BehaviorRegistry.register(Session, :join, Chat)
    :ok = BehaviorRegistry.register(Session, :leave, Chat)
    :ok = BehaviorRegistry.register(User, :receive, Chat)
    :ok = BehaviorRegistry.register(Agent, :receive, Chat)
    # Phase 6 PR 2: Identity behavior registration (list_caps / has_cap?)
    # moved to ezagent_domain_identity.Application — Identity is the identity
    # domain's concern, not chat's.

    # PR #146 (SPEC v2 §5.7) — session-scoped routing rule mutations
    # dispatch to `session://<name>?action=routing.<action>` against
    # the Session Kind. The synthetic `routing-admin://default`
    # singleton is dissolved; rules naturally cap-scope to their session.
    alias Ezagent.Behavior.Routing, as: RB

    Enum.each(RB.actions(), fn action ->
      :ok = BehaviorRegistry.register(Session, action, RB)
    end)

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
      {Ezagent.Kind.Server, {kind_module, args}},
      id: child_id
    )
  end

  # Phase 8c PR-E (Allen 2026-05-20) — every session in KindRegistry MUST
  # have a WorkspaceRegistry binding (per architectural invariant).
  # session://main is a static supervisor child (line 80 above) — it
  # skips `Ezagent.Entity.Session.spawn_from_template/2` which would
  # have done the binding. This post-boot step closes that gap so the
  # default session participates in the same workspace contract as
  # every other session.
  defp bind_default_session_to_default_workspace do
    session_uri = Session.default_uri()
    {:ok, workspace_uri} = Ezagent.WorkspaceRegistry.default_workspace_uri()
    :ok = Ezagent.WorkspaceRegistry.bind(session_uri, workspace_uri)
  end

  defp admin_user_joins_default_session do
    admin_uri = User.admin_uri()
    session_uri = Session.default_uri()
    target = URI.new!("#{URI.to_string(session_uri)}?action=chat.join")

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

  # PR #149 (SPEC v2 §5.14) — agent flavor resolution without
  # `Ezagent.AgentTypeRegistry`. Three-step lookup:
  #
  # 1. Snapshot — restart case. KindSnapshot stores `kind_type` for
  #    every persisted Kind; the chat plugin maps it back to the Kind
  #    module. Fast, single DB row by URI.
  # 2. Workspace template — first-spawn-after-template-creation case.
  #    Walks `Ezagent.Workspace.Store.list_all/0` looking for a
  #    session_template whose `agent_uri` matches; the template's
  #    `class` string ("cc.agent" / "curl.agent" / ...) maps to a Kind
  #    module.
  # 3. Flavor prefix — boot-time auto-spawn / CLI-driven spawn case.
  #    The URI's name segment is `<flavor>_<name>`; the chat plugin
  #    knows the three built-in flavors (cc/curl/echo). Future agent
  #    flavors register their Template Class in step 2; the prefix
  #    fallback handles legacy / direct-spawn paths.
  defp spawn_agent(%URI{} = uri) do
    case lookup_kind_module_for_agent(uri) do
      {:ok, kind_module} ->
        DynamicSupervisor.start_child(
          EzagentDomainChat.AgentSupervisor,
          {Ezagent.Kind.Server, {kind_module, %{uri: uri}}}
        )

      :error ->
        {:error, {:no_kind_module_for_agent, URI.to_string(uri)}}
    end
  end

  defp lookup_kind_module_for_agent(%URI{} = uri) do
    uri_str = URI.to_string(uri)

    with :error <- lookup_via_snapshot(uri_str),
         :error <- lookup_via_workspace_template(uri_str),
         :error <- lookup_via_flavor_prefix(uri) do
      :error
    else
      {:ok, _mod} = ok -> ok
    end
  end

  defp lookup_via_snapshot(uri_str) do
    case Ezagent.Ecto.KindSnapshot.get(uri_str) do
      %Ezagent.Ecto.KindSnapshot{kind_type: kt} when is_binary(kt) and kt != "" ->
        case kind_module_from_kind_type(kt) do
          nil -> :error
          mod -> {:ok, mod}
        end

      _ ->
        :error
    end
  rescue
    # DB unavailable at boot — fall through to next resolver step. The
    # snapshot is an optimization; missing it just means we hit step 2/3.
    _ -> :error
  end

  defp lookup_via_workspace_template(uri_str) do
    if Code.ensure_loaded?(Ezagent.Workspace.Store) do
      Ezagent.Workspace.Store.list_all()
      |> Enum.find_value(fn ws ->
        ws.session_templates
        |> Map.values()
        |> Enum.find_value(fn tmpl ->
          case tmpl do
            %{"agent_uri" => ^uri_str, "class" => class} when is_binary(class) ->
              kind_module_from_class(class)

            %{"agent_uri" => ^uri_str, class: class} when is_binary(class) ->
              kind_module_from_class(class)

            _ ->
              nil
          end
        end)
      end)
      |> case do
        nil -> :error
        mod -> {:ok, mod}
      end
    else
      :error
    end
  rescue
    # Same boot-time DB unavailability tolerance as step 1.
    _ -> :error
  end

  defp lookup_via_flavor_prefix(%URI{host: "agent", path: "/" <> name}) when name != "" do
    case String.split(name, "_", parts: 2) do
      [flavor, rest] when flavor != "" and rest != "" ->
        case kind_module_from_flavor(flavor) do
          nil -> :error
          mod -> {:ok, mod}
        end

      _ ->
        :error
    end
  end

  defp lookup_via_flavor_prefix(_), do: :error

  # KindSnapshot.kind_type is `to_string(kind_module.type_name())` per
  # the Snapshot writer (kind/snapshot.ex). Map back to the Kind module.
  defp kind_module_from_kind_type("agent"), do: Ezagent.Entity.Agent
  defp kind_module_from_kind_type("curl_agent"), do: Ezagent.Entity.CurlAgent
  defp kind_module_from_kind_type("echo"), do: Ezagent.Entity.Echo
  defp kind_module_from_kind_type(_), do: nil

  # Template Class names (e.g. "cc.agent" registered by ezagent_plugin_cc;
  # "curl.agent" registered by ezagent_plugin_curl_agent) map to Kind
  # modules. Echo has no Template Class — Echo agents live via boot-time
  # auto-spawn + snapshot.
  defp kind_module_from_class("cc.agent"), do: Ezagent.Entity.Agent
  defp kind_module_from_class("curl.agent"), do: Ezagent.Entity.CurlAgent
  defp kind_module_from_class("echo.agent"), do: Ezagent.Entity.Echo
  defp kind_module_from_class(_), do: nil

  # Flavor prefix (`cc_` / `curl_` / `echo_` / `test_`) → Kind module.
  # `test` agents (used as mention/routing fixtures) map to Entity.Agent
  # so the SpawnRegistry round-trip works in tests.
  defp kind_module_from_flavor("cc"), do: Ezagent.Entity.Agent
  defp kind_module_from_flavor("curl"), do: Ezagent.Entity.CurlAgent
  defp kind_module_from_flavor("echo"), do: Ezagent.Entity.Echo
  defp kind_module_from_flavor("test"), do: Ezagent.Entity.Agent
  defp kind_module_from_flavor(_), do: nil
end
