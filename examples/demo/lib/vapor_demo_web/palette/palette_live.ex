defmodule VaporDemoWeb.Palette.PaletteLive do
  @moduledoc """
  The ⌘K command palette: a sticky LiveView the layout renders once, which
  lives on across navigation. It's hybrid: Vue opens it and filters in the
  browser, and the server keeps its list of issues current.
  """

  use Phoenix.LiveView
  use PhoenixVapor, file: "Palette.vue"

  alias VaporDemo.Tracker

  def mount(_params, _session, socket) do
    if connected?(socket), do: Tracker.subscribe()
    {:ok, socket |> assign(teams: Enum.map(Tracker.teams(), &Map.take(&1, [:key, :name]))) |> refresh()}
  end

  def handle_info(:tracker_changed, socket), do: {:noreply, refresh(socket)}

  defp refresh(socket) do
    issues =
      for team <- Tracker.teams(), issue <- Tracker.issues(team.key),
          do: Map.take(issue, [:key, :title, :status])

    assign(socket, issues: issues)
  end
end
