defmodule VaporDemoWeb.Router do
  use VaporDemoWeb, :router

  import PhoenixReplay.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {VaporDemoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    # Where a visit came from, for the recordings.
    plug PhoenixReplay.Plug
  end

  scope "/", VaporDemoWeb do
    pipe_through :browser

    # Every page is recorded for session replay; see /dev/replay.
    live_session :demo, on_mount: [PhoenixReplay.Recorder] do
      live "/", HomeLive

      # A small workspace, the demo's app.
      live "/contacts", Workspace.ContactsLive
      live "/settings", Workspace.SettingsLive

      # One page per way to use PhoenixVapor.
      live "/modes/sigil", Modes.SigilLive
      live "/modes/server", Modes.ServerLive
      live "/modes/reactive", Modes.ReactiveLive
      live "/modes/hybrid", Modes.HybridLive
      live "/modes/full", Modes.FullLive
      live "/modes/compare", Modes.CompareLive
    end
  end

  # The session replay dashboard, in development only: recordings hold the
  # pages' data.
  if Application.compile_env(:vapor_demo, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      phoenix_replay "/replay"
    end
  end
end
