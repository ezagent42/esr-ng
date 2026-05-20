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
  end

  # /admin* requires login (Phase 4-completion Spec 05 §A.2.3 +
  # PR #123 hardening: live_session on_mount gates the WS reconnect
  # path that bypasses the HTTP Plug pipeline).
  # PR-B: file download route for chat compose uploads. Mounted in the
  # EzagentWeb scope (so the controller resolves correctly), under the
  # same RequireEntity plug as /admin/*.
  scope "/", EzagentWeb do
    pipe_through [:browser, EzagentWeb.Plugs.RequireEntity]

    get "/admin/uploads/:filename", UploadsController, :show
  end

  scope "/", EzagentPluginLiveview do
    pipe_through [:browser, EzagentWeb.Plugs.RequireEntity]

    live_session :require_entity, on_mount: {EzagentWeb.LiveAuth, :require_entity} do
      live "/admin", AdminLive

      # Phase 4d: Workspace management surfaces. Separate LV (not a tab
      # inside admin_live) per Phase 4 D2 — cluster-shape config is a
      # different surface than per-session chat.
      live "/admin/workspaces", WorkspacesLive
      live "/admin/workspaces/:name", WorkspaceDetailLive

      # Phase 4-completion PR 7: global RoutingRegistry rule editor.
      live "/admin/routing", RoutingLive

      # Phase 5 PR 2: Users LV.
      live "/admin/users", UsersLive
      # Phase 6 PR 6: per-user cap-grant UI.
      live "/admin/users/:uri/caps", UserCapsLive
      # PR #126: per-user API key management UI (for curl-agent etc.).
      live "/admin/users/:uri/api-keys", UserApiKeysLive

      # Phase 5 PR 3: Snapshots observability.
      live "/admin/snapshots", SnapshotsLive

      # PR #149 (S-5 entity-agnostic): unified live registry replaces
      # the agent-only list page. Detail + terminal routes stay at
      # `/admin/agents/:uri/...` because they're PTY-specific.
      live "/admin/entities", EntitiesLive
      live "/admin/agents/:uri", AgentDetailLive

      # Real Phase 5 PR 4: Pty-Web (xterm.js in browser).
      live "/admin/agents/:uri/terminal", PtyTerminalLive

      # Phase 6 PR 10: auto-derived list/detail for any Kind.
      live "/admin/auto/:kind", AutoDeriveLive
      live "/admin/auto/:kind/:uri", AutoDeriveLive

      # Phase 6 PR 15: Feishu open_id ↔ local user bindings admin UI.
      live "/admin/feishu/bindings", FeishuBindingsLive
    end
  end

  # Liveness probe — plain JSON, no ESR dispatch path involved.
  scope "/", EzagentWeb do
    pipe_through :api

    get "/_health", HealthController, :index
  end

  # Phase 7 PR 32c (rebrand-4): v1 prototype CC bridge HTTP routes
  # deleted alongside their controller. Production CC bridges connect
  # via the v2 `/cc_socket` Phoenix.Channel (token-authenticated by
  # EzagentPluginCc.TokenStore), defined in EzagentWeb.Endpoint.
  scope "/api", EzagentWeb do
    pipe_through :api

    # Phase 4-plus follow-up (2026-05-17): CC hook error reporting.
    # No auth — see CcEventsController moduledoc for trust-boundary
    # rationale (the agent the hook reports about may be down).
    post "/cc-events", CcEventsController, :report
  end

  # (Post-Phase-5 cleanup, Allen 2026-05-17: the `/api/cli/exec` HTTP
  # endpoint and CliController are gone. CLI now reaches the runtime via
  # distributed Erlang RPC — see Ezagent.Runtime + Mix.Tasks.Ezagent. LV ↔
  # runtime was never HTTP either — LV runs in the same BEAM.)

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

  # Other scopes may use custom stacks.
  # scope "/api", EzagentWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:ezagent_web, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: EzagentWeb.Telemetry
    end
  end
end
