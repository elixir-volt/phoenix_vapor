defmodule VaporDemoWeb.Router do
  use VaporDemoWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {VaporDemoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", VaporDemoWeb do
    pipe_through :browser

    live_session :demo do
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
end
