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

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", VaporDemoWeb do
    pipe_through :browser

    live "/", HomeLive
    live "/counter", CounterLive
    live "/todo", TodoLive
    live "/showcase", ShowcaseLive
    live "/reactive", ReactiveCounterLive
    live "/reactive-list", ReactiveListLive
    live "/dialog", DialogLive
    live "/vapor-test", VaporTestLive
    live "/compare", CompareLive
    live "/hybrid", HybridUsersLive
    live "/contacts", HybridContactsLive
    live "/search", HybridSearchLive
  end

  # Other scopes may use custom stacks.
  # scope "/api", VaporDemoWeb do
  #   pipe_through :api
  # end
end
