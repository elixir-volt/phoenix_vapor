defmodule LiveVueNextDemoWeb.Router do
  use LiveVueNextDemoWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {LiveVueNextDemoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", LiveVueNextDemoWeb do
    pipe_through :browser

    live "/", HomeLive
    live "/counter", CounterLive
    live "/todo", TodoLive
    live "/showcase", ShowcaseLive
    live "/reactive", ReactiveCounterLive
    live "/vapor-test", VaporTestLive
  end

  # Other scopes may use custom stacks.
  # scope "/api", LiveVueNextDemoWeb do
  #   pipe_through :api
  # end
end
