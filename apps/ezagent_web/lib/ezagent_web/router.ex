defmodule EzagentWeb.Router do
  use EzagentWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {EzagentWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", EzagentWeb do
    pipe_through :browser

    live "/", HomeLive

    # Phase 4-completion Spec 05 §A.2.3 — controller-rendered login.
    get "/login", SessionController, :new
    post "/login", SessionController, :create
    get "/login/credentials", SessionController, :credentials_new
    post "/login/credentials", SessionController, :credentials_create
    delete "/logout", SessionController, :delete
    post "/logout", SessionController, :delete
    get "/auth/magic/:token", MagicLinkController, :consume
    get "/register/complete", RegistrationController, :complete_new
    post "/register/complete", RegistrationController, :complete_create
  end

  # /admin* requires login (Phase 4-completion Spec 05 §A.2.3 +
  # PR #123 hardening: live_session on_mount gates the WS reconnect
  # path that bypasses the HTTP Plug pipeline).
  # PR-B: file download route for chat compose uploads. Mounted in the
  # EzagentWeb scope (so the controller resolves correctly), under the
  # same RequireEntity plug as the LV scope below.
  scope "/", EzagentWeb do
    pipe_through [:browser, EzagentWeb.Plugs.RequireEntity]

    get "/admin/uploads/:filename", UploadsController, :show
  end

  scope "/", EzagentPluginLiveview do
    pipe_through [:browser, EzagentWeb.Plugs.RequireEntity]

    live_session :require_entity, on_mount: {EzagentWeb.LiveAuth, :require_entity} do
      # Phase 8 polish — IA refactor (Allen 2026-05-20). Business-feature
      # routes live at top level. `/admin/*` is reserved for the admin
      # dashboard (KPIs + sysadmin sub-pages: logs, registry, snapshots).

      # Sessions Activity (was /admin in Phase 8).
      live "/sessions", AdminLive

      # Admin dashboard + sysadmin sub-pages.
      live "/admin", AdminDashboardLive
      live "/admin/logs", ObservabilityLive
      live "/admin/registry", EntitiesLive
      live "/admin/snapshots", SnapshotsLive

      # Workspaces Activity.
      live "/workspaces", WorkspacesLive
      live "/workspaces/:name", WorkspaceDetailLive

      # Routing Activity.
      live "/routing", RoutingLive

      # Identities Activity (address book: users + agents are entity sub-types).
      live "/identities", IdentitiesLive
      live "/identities/users", UsersLive
      live "/identities/users/:uri/caps", UserCapsLive
      live "/identities/users/:uri/api-keys", UserApiKeysLive
      live "/identities/agents/:uri", AgentDetailLive
      live "/identities/agents/:uri/terminal", PtyTerminalLive

      # Plugins Activity.
      live "/plugins", PluginsLive
      live "/plugins/feishu/bindings", FeishuBindingsLive
      live "/plugins/auto/:kind", AutoDeriveLive
      live "/plugins/auto/:kind/:uri", AutoDeriveLive

      # Top-level Profile + Settings (reached via avatar dropdown).
      live "/profile", ProfileLive
      live "/settings", SettingsLive
    end
  end

  # Liveness probe — plain JSON, no ESR dispatch path involved.
  scope "/", EzagentWeb do
    pipe_through :api

    get "/_health", HealthController, :index
  end

  scope "/api", EzagentWeb do
    pipe_through :api

    # Phase 4-plus follow-up (2026-05-17): CC hook error reporting.
    # No auth — see CcEventsController moduledoc for trust-boundary
    # rationale (the agent the hook reports about may be down).
    post "/cc-events", CcEventsController, :report
  end

  # Phase 5 PR 6: Feishu webhook receiver. The ONLY touch
  # ezagent_plugin_feishu makes to ezagent_web — explicit exception per SPEC v2
  # north star ("beyond webhook route registration").
  forward "/api/feishu/webhook", EzagentPluginFeishu.WebhookPlug

  # Phase 6 PR 9: canonical auto-derived JSON API. Single controller
  # dispatches every `{kind, action}` registered in BehaviorRegistry.
  # GET /api/v1 = introspection (route catalog + interfaces).
  # POST /api/v1/:kind/:action = invoke.
  scope "/api/v1", EzagentWeb do
    pipe_through :api

    get "/", ApiV1Controller, :index
    post "/:kind/:action", ApiV1Controller, :invoke
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:ezagent_web, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: EzagentWeb.Telemetry
    end
  end
end
