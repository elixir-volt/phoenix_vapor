defmodule VaporDemoWeb.Workspace.SettingsLive do
  @moduledoc """
  The project's settings. Tabs, the role filter and the notification switches
  are the browser's; renaming the project and removing a member go through the
  server, and every open page sees them.
  """

  use VaporDemoWeb, :live_view
  use PhoenixVapor, file: "ProjectSettings.vue"

  alias VaporDemo.Projects

  def mount(_params, _session, socket) do
    if connected?(socket), do: Projects.subscribe()

    {:ok,
     assign(socket,
       page_title: "Settings",
       project: Projects.project(),
       members: Projects.members()
     )}
  end

  def handle_event("saveName", %{"newName" => name}, socket) do
    state = Projects.rename(name)
    {:noreply, assign(socket, project: state.project)}
  end

  def handle_event("removeMember", %{"id" => id}, socket) do
    state = Projects.remove_member(id)
    {:noreply, assign(socket, members: state.members)}
  end

  def handle_info({:project, project, members}, socket),
    do: {:noreply, assign(socket, project: project, members: members)}
end
