defmodule VaporDemoWeb.Modes.ServerLive do
  @moduledoc """
  A server-only `.vue` file: a template with props and no client state,
  rendered by the server alone, with the rest of the LiveView in Elixir.
  """

  use VaporDemoWeb, :live_view
  use PhoenixVapor, file: "Team.vue"

  alias VaporDemo.Projects

  def mount(_params, _session, socket) do
    if connected?(socket), do: Projects.subscribe()

    {:ok,
     assign(socket,
       page_title: "Server-only .vue",
       project: Projects.project(),
       members: Projects.members()
     )}
  end

  def handle_info({:project, project, members}, socket),
    do: {:noreply, assign(socket, project: project, members: members)}
end
