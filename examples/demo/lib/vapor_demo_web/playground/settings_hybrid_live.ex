defmodule VaporDemoWeb.Playground.SettingsHybridLive do
  use VaporDemoWeb, :live_view
  use PhoenixVapor, file: "ProjectSettings.vue"

  alias VaporDemoWeb.Playground.Data

  def mount(_params, _session, socket) do
    {:ok, assign(socket, project: Data.project(), members: Data.members())}
  end

  def handle_event("saveName", %{"newName" => name}, socket) do
    {:noreply, update(socket, :project, &%{&1 | name: name})}
  end

  def handle_event("removeMember", %{"id" => id}, socket) do
    {:noreply, update(socket, :members, &Enum.reject(&1, fn m -> m.id == id end))}
  end
end
