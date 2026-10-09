defmodule VaporDemoWeb.Board.BoardLive do
  @moduledoc """
  A team's board. Filtering and dragging happen in the browser; a move goes
  through the server, and every open board follows.
  """

  use VaporDemoWeb, :live_view
  use PhoenixVapor, file: "Board.vue"

  alias VaporDemo.Tracker
  alias VaporDemoWeb.Activity

  def mount(%{"team" => key}, _session, socket) do
    case Tracker.team(key) do
      nil ->
        {:ok, push_navigate(socket, to: "/engineering/board")}

      team ->
        {:ok,
         socket
         |> assign(
           page_title: "#{team.name} board",
           team: Map.take(team, [:key, :name]),
           people: Tracker.people(),
           me: Tracker.me().id
         )
         |> refresh()}
    end
  end

  def handle_event("moveIssue", %{"id" => id, "status" => status}, socket) do
    if status in Tracker.statuses(), do: Tracker.move(id, status)
    {:noreply, refresh(socket)}
  end

  def handle_info(:tracker_changed, socket), do: {:noreply, refresh(socket)}

  defp refresh(socket) do
    assign(socket, issues: Tracker.issues(socket.assigns.team.key), activity: Activity.entries())
  end
end
