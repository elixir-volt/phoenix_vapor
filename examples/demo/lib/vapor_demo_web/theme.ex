defmodule VaporDemoWeb.Theme do
  @moduledoc """
  The theme a visitor chose, `"dark"` or `"light"`, kept on the server, so
  session recordings carry it like any other assign. As PhoenixReplay's
  example app does it.

  The plug reads it from the `theme` cookie into the session and `@theme`,
  which the root layout renders as `data-theme` on `<html>`. The `on_mount`
  hook gives each LiveView `@theme` and handles the sidebar's `"theme"`
  event: it updates the assign and pushes `"theme"`, whose listener in
  `shell.ts` sets `data-theme` at once and keeps the choice in the cookie for
  the next page load.

  A replay needs nothing more: the player renders the root layout again with
  each moment's assigns, its `frame_layout` in the router, so the replayed
  page takes the theme the session had then.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, push_event: 3]

  @behaviour Plug

  @themes ~w(dark light)

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    conn = Plug.Conn.fetch_cookies(conn)
    theme = chosen(conn.cookies["theme"])

    conn
    |> Plug.Conn.put_session("theme", theme)
    |> Plug.Conn.assign(:theme, theme)
  end

  @doc "Gives a LiveView `@theme` and handles the switch."
  def on_mount(:default, _params, session, socket) do
    socket =
      socket
      |> assign(:theme, chosen(session["theme"]))
      |> attach_hook(:theme, :handle_event, &handle_event/3)

    {:cont, socket}
  end

  defp handle_event("theme", %{"theme" => theme}, socket) when theme in @themes,
    do: {:halt, socket |> assign(:theme, theme) |> push_event("theme", %{theme: theme})}

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  defp chosen(theme) when theme in @themes, do: theme
  defp chosen(_theme), do: "dark"
end
