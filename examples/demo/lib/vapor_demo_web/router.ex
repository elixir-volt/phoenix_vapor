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

    get "/", Redirect, to: "/engineering/board"

    # Every page is recorded for session replay; see /dev/replay.
    live_session :tracker, on_mount: [PhoenixReplay.Recorder, VaporDemoWeb.Shell] do
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

      phoenix_replay "/replay"
    end
  end
end
