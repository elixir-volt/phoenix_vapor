defmodule VaporDemoWeb.PageController do
  use VaporDemoWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
