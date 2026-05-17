defmodule EsrWeb.Router do
  use EsrWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {EsrWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # SSE pipeline — accepts text/event-stream for streaming endpoints.
  pipeline :sse do
    plug :accepts, ["event-stream"]
  end

  scope "/", EsrWeb do
    pipe_through :browser

    live "/", HomeLive

    # Phase 4-completion Spec 05 §A.2.3 — controller-rendered login.
    get "/login", SessionController, :new
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete
    post "/logout", SessionController, :delete
  end

  # /admin* requires login (Phase 4-completion Spec 05 §A.2.3).
  scope "/", EsrPluginEzagent do
    pipe_through [:browser, EsrWeb.Plugs.RequireUser]

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

    # Phase 5 PR 3: Snapshots observability.
    live "/admin/snapshots", SnapshotsLive

    # Real Phase 5 PR 3: PTY agent live status.
    live "/admin/agents", AgentsLive
    live "/admin/agents/:uri", AgentDetailLive

    # Real Phase 5 PR 4: Pty-Web (xterm.js in browser).
    live "/admin/agents/:uri/terminal", PtyTerminalLive

    # Phase 6 PR 10: auto-derived list/detail for any Kind.
    live "/admin/auto/:kind", AutoDeriveLive
    live "/admin/auto/:kind/:uri", AutoDeriveLive
  end

  # Liveness probe — plain JSON, no ESR dispatch path involved.
  scope "/", EsrWeb do
    pipe_through :api

    get "/_health", HealthController, :index
  end

  # Phase 1 v1_prototype: CC bridge announce endpoint (Phase 5 will use
  # a Phoenix Channel join handshake instead — this scope is throwaway).
  scope "/api", EsrWeb do
    pipe_through :api

    post "/cc-bridge/announce", CcBridgeAnnounceController, :announce
    delete "/cc-bridge/announce/:bridge_id", CcBridgeAnnounceController, :disconnect
    post "/cc-bridge/reply", CcBridgeAnnounceController, :reply

    # Phase 4-plus follow-up (2026-05-17): CC hook error reporting.
    # No auth — see CcEventsController moduledoc for trust-boundary
    # rationale (the agent the hook reports about may be down).
    post "/cc-events", CcEventsController, :report

  end

  # (Post-Phase-5 cleanup, Allen 2026-05-17: the `/api/cli/exec` HTTP
  # endpoint and CliController are gone. CLI now reaches the runtime via
  # distributed Erlang RPC — see Esr.Runtime + Mix.Tasks.Esr. LV ↔
  # runtime was never HTTP either — LV runs in the same BEAM.)

  # Phase 5 PR 6: Feishu webhook receiver. The ONLY touch
  # esr_plugin_feishu makes to esr_web — explicit exception per SPEC v2
  # north star ("beyond webhook route registration").
  forward "/api/feishu/webhook", EsrPluginFeishu.WebhookPlug

  # Phase 6 PR 9: canonical auto-derived JSON API. Single controller
  # dispatches every `{kind, action}` registered in BehaviorRegistry.
  # GET /api/v1 = introspection (route catalog + interfaces).
  # POST /api/v1/:kind/:action = invoke.
  scope "/api/v1", EsrWeb do
    pipe_through :api

    get "/", ApiV1Controller, :index
    post "/:kind/:action", ApiV1Controller, :invoke
  end

  # SSE route — separate scope because its accepts header differs.
  scope "/api", EsrWeb do
    pipe_through :sse

    get "/cc-bridge/events", CcBridgeAnnounceController, :events_sse
  end

  # Other scopes may use custom stacks.
  # scope "/api", EsrWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:esr_web, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: EsrWeb.Telemetry
    end
  end
end
