defmodule VaporDemo.Tracker do
  @moduledoc """
  The tracker's teams, people, issues, comments and activity, kept in memory
  for the demo. Every change is broadcast, so every open page follows it, and
  `reset/0` restores the seed.

  Issues are plain maps with string keys' values, as the browser sees them:
  `status` is one of `statuses/0` and `priority` one of `priorities/0`.
  """

  use Agent

  alias VaporDemo.Tracker.Seed

  @topic "tracker"

  @statuses ~w(backlog todo in_progress in_review done)
  @priorities ~w(none low medium high urgent)

  def start_link(_opts), do: Agent.start_link(&Seed.state/0, name: __MODULE__)

  @doc "The statuses an issue moves through, in board order."
  def statuses, do: @statuses

  @doc "The priorities, lowest first."
  def priorities, do: @priorities

  @doc "The person the demo acts as."
  def me, do: Agent.get(__MODULE__, &hd(&1.people))

  def people, do: Agent.get(__MODULE__, & &1.people)
  def teams, do: Agent.get(__MODULE__, & &1.teams)

  def team(key), do: Enum.find(teams(), &(&1.key == key))

  @doc "A team's issues, newest first."
  def issues(team_key) do
    Agent.get(__MODULE__, fn state ->
      state.issues |> Enum.filter(&(&1.team == team_key)) |> Enum.sort_by(& &1.number, :desc)
    end)
  end

  @doc "The issue with a key such as `ENG-142`, or nil."
  def issue(key), do: Agent.get(__MODULE__, fn state -> Enum.find(state.issues, &(&1.key == key)) end)

  @doc "An issue's comments, oldest first."
  def comments(issue_id) do
    Agent.get(__MODULE__, fn state -> Enum.filter(state.comments, &(&1.issue_id == issue_id)) end)
  end

  @doc "The latest activity across the workspace, newest first."
  def activity(limit \\ 12), do: Agent.get(__MODULE__, &Enum.take(&1.activity, limit))

  @doc "Moves an issue to a status."
  def move(id, status) when status in @statuses do
    change(id, %{status: status}, fn issue -> "moved #{issue.key} to #{label(status)}" end)
  end

  @doc "Sets an issue's priority."
  def prioritize(id, priority) when priority in @priorities do
    change(id, %{priority: priority}, fn issue -> "set the priority of #{issue.key}" end)
  end

  @doc "Assigns an issue to a person, or nobody with nil."
  def assign_to(id, person_id) do
    change(id, %{assignee_id: person_id}, fn issue -> "assigned #{issue.key}" end)
  end

  @doc "Changes an issue's title and description."
  def edit(id, %{title: title, description: description}) do
    title = String.trim(title)

    if title == "",
      do: :error,
      else:
        change(id, %{title: title, description: description}, fn issue ->
          "edited #{issue.key}"
        end)
  end

  @doc "Adds a comment by the demo's person."
  def comment(issue_id, body) do
    body = String.trim(body)

    if body == "" do
      :error
    else
      update(fn state ->
        issue = Enum.find(state.issues, &(&1.id == issue_id))
        me = hd(state.people)

        comment = %{
          id: length(state.comments) + 1,
          issue_id: issue_id,
          author_id: me.id,
          body: body,
          at: now()
        }

        state
        |> Map.update!(:comments, &(&1 ++ [comment]))
        |> log(me, "commented on #{issue.key}")
      end)
    end
  end

  @doc """
  Creates an issue in a team's backlog from a title, and optionally a
  description and priority. Returns `{:ok, issue}`, or `:error` for a blank
  title or an unknown team.
  """
  def create(team_key, %{title: title} = attrs) do
    title = String.trim(title)
    priority = if attrs[:priority] in @priorities, do: attrs[:priority], else: "none"

    if title == "" or team(team_key) == nil do
      :error
    else
      issue =
        Agent.get_and_update(__MODULE__, fn state ->
          me = hd(state.people)
          team = Enum.find(state.teams, &(&1.key == team_key))

          number =
            state.issues
            |> Enum.filter(&(&1.team == team_key))
            |> Enum.map(& &1.number)
            |> Enum.max(fn -> 0 end)
            |> Kernel.+(1)

          issue = %{
            id: Enum.max_by(state.issues, & &1.id, fn -> %{id: 0} end).id + 1,
            team: team_key,
            number: number,
            key: "#{team.prefix}-#{number}",
            title: title,
            description: String.trim(attrs[:description] || ""),
            status: "backlog",
            priority: priority,
            assignee_id: nil,
            labels: [],
            updated_at: now()
          }

          state = state |> Map.update!(:issues, &[issue | &1]) |> log(me, "created #{issue.key}")
          {issue, state}
        end)

      Phoenix.PubSub.broadcast(VaporDemo.PubSub, @topic, :tracker_changed)
      {:ok, issue}
    end
  end

  @doc "Restores the seed, as the demo starts."
  def reset, do: update(fn _state -> Seed.state() end)

  @doc "Subscribes the caller to `:tracker_changed` on every change."
  def subscribe, do: Phoenix.PubSub.subscribe(VaporDemo.PubSub, @topic)

  @doc "A status's name, as the board shows it."
  def label("backlog"), do: "Backlog"
  def label("todo"), do: "Todo"
  def label("in_progress"), do: "In Progress"
  def label("in_review"), do: "In Review"
  def label("done"), do: "Done"

  defp change(id, changes, describe) do
    update(fn state ->
      case Enum.find(state.issues, &(&1.id == id)) do
        nil ->
          state

        issue ->
          issue = Map.merge(issue, Map.put(changes, :updated_at, now()))

          state
          |> Map.update!(:issues, fn issues ->
            Enum.map(issues, &if(&1.id == id, do: issue, else: &1))
          end)
          |> log(hd(state.people), describe.(issue))
      end
    end)
  end

  defp log(state, person, what) do
    entry = %{id: System.unique_integer([:positive]), person_id: person.id, what: what, at: now()}
    Map.update!(state, :activity, &Enum.take([entry | &1], 50))
  end

  defp update(fun) do
    Agent.update(__MODULE__, fun)
    Phoenix.PubSub.broadcast(VaporDemo.PubSub, @topic, :tracker_changed)
    :ok
  end

  defp now, do: System.system_time(:second)
end
