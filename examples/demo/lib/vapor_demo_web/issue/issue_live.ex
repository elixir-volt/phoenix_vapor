defmodule VaporDemoWeb.Issue.IssueLive do
  @moduledoc """
  An issue. Its title and description are edited in the browser and saved
  through the server; its properties and comments change through server
  actions, and every open page follows.
  """

  use VaporDemoWeb, :live_view
  use PhoenixVapor, file: "Issue.vue"

  alias VaporDemo.Tracker
  alias VaporDemoWeb.Activity

  def mount(%{"key" => key}, _session, socket) do
    case Tracker.issue(key) do
      nil ->
        {:ok, socket |> put_flash(:error, "There's no issue #{key}.") |> push_navigate(to: "/")}

      issue ->
        team = Tracker.team(issue.team)

        {:ok,
         socket
         |> assign(
           page_title: "#{issue.key} #{issue.title}",
           key: key,
           team: Map.take(team, [:key, :name]),
           people: Tracker.people(),
           me: Tracker.me()
         )
         |> refresh()}
    end
  end

  def handle_event("editIssue", %{"title" => title, "description" => description}, socket) do
    Tracker.edit(socket.assigns.issue.id, %{title: title, description: description})
    {:noreply, refresh(socket)}
  end

  def handle_event("setStatus", %{"status" => status}, socket) do
    if status in Tracker.statuses(), do: Tracker.move(socket.assigns.issue.id, status)
    {:noreply, refresh(socket)}
  end

  def handle_event("setPriority", %{"priority" => priority}, socket) do
    if priority in Tracker.priorities(), do: Tracker.prioritize(socket.assigns.issue.id, priority)
    {:noreply, refresh(socket)}
  end

  def handle_event("setAssignee", %{"assignee" => assignee}, socket) do
    person =
      Enum.find(Tracker.people(), &(to_string(&1.id) == assignee))

    Tracker.assign_to(socket.assigns.issue.id, person && person.id)
    {:noreply, refresh(socket)}
  end

  def handle_event("addComment", %{"body" => body}, socket) do
    Tracker.comment(socket.assigns.issue.id, body)
    {:noreply, refresh(socket)}
  end

  def handle_info(:tracker_changed, socket), do: {:noreply, refresh(socket)}

  defp refresh(socket) do
    issue = Tracker.issue(socket.assigns.key)
    people = Map.new(socket.assigns.people, &{&1.id, &1})
    now = System.system_time(:second)

    comments =
      for comment <- Tracker.comments(issue.id) do
        %{
          id: comment.id,
          author: people[comment.author_id],
          body: comment.body,
          when: Activity.ago(now - comment.at)
        }
      end

    issue =
      Map.take(issue, [:id, :key, :title, :description, :status, :priority, :assignee_id, :labels])

    assign(socket, issue: issue, comments: comments)
  end
end
