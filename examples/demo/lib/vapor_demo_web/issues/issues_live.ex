defmodule VaporDemoWeb.Issues.IssuesLive do
  @moduledoc """
  A list of issues: a team's, or the ones assigned to the demo's person.
  Sorting and selection happen in the browser; a bulk move goes through the
  server.
  """

  use VaporDemoWeb, :live_view
  use PhoenixVapor, file: "Issues.vue"

  alias VaporDemo.Tracker
  alias VaporDemoWeb.Activity

  @ranks %{"urgent" => 4, "high" => 3, "medium" => 2, "low" => 1, "none" => 0}

  def mount(params, _session, socket) do
    socket =
      case {socket.assigns.live_action, Tracker.team(params["team"])} do
        {:mine, _team} ->
          assign(socket, page_title: "My issues", heading: "My issues", parent: nil, team: nil)

        {:team, nil} ->
          push_navigate(socket, to: "/")

        {:team, team} ->
          assign(socket,
            page_title: "#{team.name} issues",
            heading: "Issues",
            parent: %{href: "/#{team.key}/board", name: team.name},
            team: team.key
          )
      end

    {:ok, refresh(socket)}
  end

  def handle_event("moveIssues", %{"ids" => ids, "status" => status}, socket)
      when is_list(ids) do
    if status in Tracker.statuses(), do: Enum.each(ids, &Tracker.move(&1, status))
    {:noreply, refresh(socket)}
  end

  def handle_info(:tracker_changed, socket), do: {:noreply, refresh(socket)}

  defp refresh(%{assigns: %{heading: _heading}} = socket) do
    people = Map.new(Tracker.people(), &{&1.id, &1})
    now = System.system_time(:second)

    issues =
      for issue <- issues(socket.assigns.team) do
        issue
        |> Map.take([:id, :key, :title, :status, :priority, :labels])
        |> Map.merge(%{
          assignee: people[issue.assignee_id],
          rank: @ranks[issue.priority],
          updated: issue.updated_at,
          when: Activity.ago(now - issue.updated_at)
        })
      end

    assign(socket, issues: issues)
  end

  defp refresh(socket), do: socket

  defp issues(nil) do
    me = Tracker.me()

    Tracker.teams()
    |> Enum.flat_map(&Tracker.issues(&1.key))
    |> Enum.filter(&(&1.assignee_id == me.id))
  end

  defp issues(team), do: Tracker.issues(team)
end
