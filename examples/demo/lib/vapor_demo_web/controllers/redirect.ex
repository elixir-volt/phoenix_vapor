defmodule VaporDemoWeb.Redirect do
  @moduledoc "A plug that redirects to `:to`, for `/`."

  @behaviour Plug

  @impl Plug
  def init(opts), do: Keyword.fetch!(opts, :to)

  @impl Plug
  def call(conn, to), do: conn |> Phoenix.Controller.redirect(to: to) |> Plug.Conn.halt()
end
