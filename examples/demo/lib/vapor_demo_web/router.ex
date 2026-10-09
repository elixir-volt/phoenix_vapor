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
    # The visitor's theme, in the session, so recordings carry it.
    plug VaporDemoWeb.Theme
  end

  scope "/", VaporDemoWeb do
    pipe_through :browser

    get "/", Redirect, to: "/engineering/board"
    # The x-ray's source view: the demo's own files, and nothing else.
    get "/source/*path", Sources, []

    # Every page is recorded for session replay; see /dev/replay.
    live_session :tracker,
      on_mount: [PhoenixReplay.Recorder, VaporDemoWeb.Theme, VaporDemoWeb.Shell] do
      live "/:team/board", Board.BoardLive
      live "/:team/issues", Issues.IssuesLive, :team
      live "/my-issues", Issues.IssuesLive, :mine
      live "/new", NewIssue.NewIssueLive
      live "/issue/:key", Issue.IssueLive
    end
  end

  # The session replay dashboard, in development only: recordings hold the
  # pages' data.
  if Application.compile_env(:vapor_demo, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      # The replay renders the root layout again at each moment, so <html>
      # takes the theme the session had, and the page its Volt-built assets.
      phoenix_replay "/replay", frame_layout: {VaporDemoWeb.Layouts, :root}
    end
  end
end
