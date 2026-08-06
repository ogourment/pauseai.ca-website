defmodule PauseAiCaWeb.Router do
  use PauseAiCaWeb, :router

  import AcceptanceHarnessWeb.Router
  import PauseAiCaWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PauseAiCaWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
    plug PauseAiCaWeb.Plugs.RecordVisit
    # Staging only: closes the site to anyone not signed in. See the plug.
    plug PauseAiCaWeb.Plugs.RequireInvited
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/" do
    pipe_through :api

    acceptance_harness_health("/health")
  end

  scope "/", PauseAiCaWeb do
    pipe_through :browser

    # Reached from a link in an email, so it must work for a signed-out visitor
    # even while the staging gate is on.
    get "/letters/confirm/:token", LetterController, :confirm

    # Leaving for PauseAI Global. Goes through us so a signed-in visitor's
    # departure can be recorded; see ActController.
    get "/act/:destination", ActController, :go

    get "/", PageController, :index
    get "/en", PageController, :en
    get "/fr", PageController, :fr
    get "/en/strategy", PageController, :strategy_en
    get "/fr/strategie", PageController, :strategy_fr
    get "/en/about", PageController, :about_en
    get "/fr/a-propos", PageController, :about_fr
    get "/en/privacy", PageController, :privacy_en
    get "/fr/confidentialite", PageController, :privacy_fr
    get "/en/montreal.html", PageController, :legacy_montreal
  end

  # Other scopes may use custom stacks.
  # scope "/api", PauseAiCaWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:pauseai_ca, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: PauseAiCaWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/admin" do
    pipe_through [:browser, :require_authenticated_user, :require_superadmin_user]

    acceptance_harness("/acceptance")
    acceptance_harness_versions("/versions")
  end

  scope "/", PauseAiCaWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{PauseAiCaWeb.UserAuth, :require_authenticated}] do
      live "/dashboard", DashboardLive, :index
      live "/en/actions", DashboardLive, :en
      live "/fr/actions", DashboardLive, :fr
      live "/en/dashboard", DashboardLive, :en
      live "/fr/tableau-de-bord", DashboardLive, :fr
      live "/en/profile", ProfileLive, :en
      live "/fr/profil", ProfileLive, :fr
      live "/admin/metrics", AdminMetricsLive, :index
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email
    end

    post "/users/update-password", UserSessionController, :update_password
    post "/bookmarks/:resource", BookmarkController, :create
  end

  scope "/", PauseAiCaWeb do
    pipe_through [:browser]

    # Public campaign pages. They work signed in or signed out, so they are not
    # in :require_authenticated_user — but they do carry :require_invited, which
    # closes them on staging only. The sign-in routes below must not carry it.
    live_session :public_content,
      on_mount: [{PauseAiCaWeb.UserAuth, :require_invited}] do
      live "/en/warning-shot", WarningShotLive, :en
      live "/fr/tir-de-semonce", WarningShotLive, :fr
      live "/en/learn", LibraryLive, :en
      live "/fr/comprendre", LibraryLive, :fr
      live "/fr/learn", LibraryLive, :fr
    end

    live_session :current_user,
      on_mount: [{PauseAiCaWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end

  scope "/", PauseAiCaWeb do
    pipe_through :browser

    get "/*path", PageController, :not_found
  end
end
