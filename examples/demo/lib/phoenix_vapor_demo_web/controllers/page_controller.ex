defmodule PhoenixVaporDemoWeb.PageController do
  use PhoenixVaporDemoWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
