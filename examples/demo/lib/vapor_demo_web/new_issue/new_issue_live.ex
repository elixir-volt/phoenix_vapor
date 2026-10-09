defmodule VaporDemoWeb.NewIssue.NewIssueLive do
  @moduledoc """
  The new issue form, in Reactive mode: `NewIssue.vue`'s refs, computeds and
  `edit` handler run on the server, in QuickBEAM. Creating the issue is
  Elixir: the one event the script doesn't handle.
  """

  use VaporDemoWeb, :live_view
  use PhoenixVapor, file: "NewIssue.vue", runtime: :reactive

  alias VaporDemo.Tracker

  def handle_event("create", params, socket) do
    attrs = %{
      title: params["title"] || "",
      description: params["description"],
      priority: params["priority"]
    }

    case Tracker.create(params["team"], attrs) do
      {:ok, issue} -> {:noreply, push_navigate(socket, to: "/issue/#{issue.key}")}
      :error -> {:noreply, put_flash(socket, :error, "An issue needs a title.")}
    end
  end
end
