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
  scope "/", EsrWebLiveview do
    pipe_through [:browser, EsrWeb.Plugs.RequireUser]

    live "/admin", AdminLive

    # Phase 4d: Workspace management surfaces. Separate LV (not a tab
    # inside admin_live) per Phase 4 D2 — cluster-shape config is a
    # different surface than per-session chat.
    live "/admin/workspaces", WorkspacesLive
    live "/admin/workspaces/:name", WorkspaceDetailLive

    # Phase 4-completion PR 7: global RoutingRegistry rule editor.
    live "/admin/routing", RoutingLive
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
