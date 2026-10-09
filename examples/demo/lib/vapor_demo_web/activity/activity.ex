defmodule VaporDemoWeb.Activity do
  @moduledoc """
  The activity rail: a server-only `.vue` file as a function component, which
  the layout renders beside pages that assign `:activity`.
  """

  use Phoenix.Component

  require PhoenixVapor.Vue

  alias VaporDemo.Tracker

  PhoenixVapor.Vue.component(:rail, "Activity.vue")

  @doc "The latest activity, as the rail shows it."
  def entries do
    people = Map.new(Tracker.people(), &{&1.id, &1})
    now = System.system_time(:second)

    for entry <- Tracker.activity() do
      person = people[entry.person_id]

      %{
        id: entry.id,
        who: person.name |> String.split() |> hd(),
        initials: person.initials,
        color: person.color,
        what: entry.what,
        when: ago(now - entry.at)
      }
    end
  end

  @doc "How long ago, in words: `just now`, `4 min ago`, `2 h ago`, `3 d ago`."
  def ago(seconds) when seconds < 60, do: "just now"
  def ago(seconds) when seconds < 3600, do: "#{div(seconds, 60)} min ago"
  def ago(seconds) when seconds < 86_400, do: "#{div(seconds, 3600)} h ago"
  def ago(seconds), do: "#{div(seconds, 86_400)} d ago"
end
