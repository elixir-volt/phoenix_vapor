defmodule PhoenixVaporDemoWeb.Router do
  use PhoenixVaporDemoWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PhoenixVaporDemoWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", PhoenixVaporDemoWeb do
    pipe_through :browser

    live "/", HomeLive
    live "/counter", CounterLive
    live "/todo", TodoLive
    live "/showcase", ShowcaseLive
    live "/reactive", ReactiveCounterLive
    live "/reactive-list", ReactiveListLive
    live "/vapor-test", VaporTestLive
    live "/compare", CompareLive
  end

  # Other scopes may use custom stacks.
  # scope "/api", PhoenixVaporDemoWeb do
  #   pipe_through :api
  # end
end
