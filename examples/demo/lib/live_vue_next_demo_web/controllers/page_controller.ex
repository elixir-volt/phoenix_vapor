defmodule LiveVueNextDemoWeb.PageController do
  use LiveVueNextDemoWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
