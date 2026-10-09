defmodule VaporDemo.E2E.SessionReplayTest do
  # PhoenixReplay records a session, and its player replays it: PhoenixVapor
  # reports the client state the render reads, refs only the browser has, and
  # the replay renders with it, the package components it folded included.
  use PhoenixTest.Playwright.Case, async: false

  alias PhoenixReplay.Trace

  @tag timeout: 60_000

  setup do
    VaporDemo.Tracker.reset()

    # Recording is off in tests; this one records.
    previous = Application.get_env(:phoenix_replay, :sample_rate)
    Application.put_env(:phoenix_replay, :sample_rate, 1.0)
    on_exit(fn -> Application.put_env(:phoenix_replay, :sample_rate, previous) end)

    %{started: DateTime.utc_now()}
  end

  test "the replay of a board session follows its filter and its moves",
       %{conn: conn, started: started} do
    conn
    |> visit("/engineering/board")
    |> assert_has(".phx-connected")
    |> assert_has("[data-v-app]")
    # The filter is the browser's; each step waits for its report.
    |> click("button", "Priority:")
    |> click("[role=menuitemradio]", "Urgent")
    |> assert_has("button", text: "Priority: Urgent")
    |> reported(~s(pv-Board: priority "urgent"))
    |> click("button", "Priority:")
    |> click("[role=menuitemradio]", "All")
    |> reported(~s(pv-Board: priority "all"))
    # A move is the server's.
    |> drag(~s([data-issue="ENG-151"]), to: ~s([data-status="todo"]))
    |> assert_has(~s([data-status="todo"] [data-issue="ENG-151"]))
    # Leaving the page ends the recorded session, which is then saved.
    |> click_link("nav[aria-label=Engineering] a", "Issues")
    |> assert_path("/engineering/issues")

    id = saved_recording(VaporDemoWeb.Board.BoardLive, started)
    key = "phoenix_vapor:pv-Board"

    conn
    |> visit("/dev/replay/#{id}?at=#{event(id, ~s(#{key}: priority "urgent"))}")
    |> assert_frame(fn page ->
      page =~ ~r/Priority: <span[^>]*>Urgent</ and page =~ ~s(data-issue="ENG-142") and
        not (page =~ ~s(data-issue="ENG-151"))
    end)
    # The move's new issues are an assign recorded after it.
    |> visit(
      "/dev/replay/#{id}?at=#{event(id, "assigns activity, issues", event(id, "moveIssue"))}"
    )
    |> assert_frame(
      &(&1 =~ ~r/data-status="todo".*data-issue="ENG-151".*data-status="in_progress"/s)
    )
  end

  # Waits for the view's running recording to have the client state report.
  defp reported(conn, view \\ VaporDemoWeb.Board.BoardLive, label, attempts \\ 50) do
    labels =
      for %{id: id} <- Trace.find(view: view, live: true),
          event <- Trace.events(id),
          do: event.label

    cond do
      Enum.any?(labels, &(&1 =~ label)) -> conn
      attempts > 0 -> Process.sleep(100) && reported(conn, view, label, attempts - 1)
      true -> flunk("no report of #{label} in #{inspect(labels)}")
    end
  end

  # The index of the first recorded event whose label has `label`, after
  # the event at `after_index`.
  defp event(id, label, after_index \\ -1) do
    case Enum.find(Trace.events(id), &(&1.index > after_index and &1.label =~ label)) do
      %{index: index} ->
        index

      nil ->
        flunk("no event #{inspect(label)} in #{inspect(Enum.map(Trace.events(id), & &1.label))}")
    end
  end

  defp saved_recording(view, started, attempts \\ 50) do
    case Trace.find(view: view, live: false, from: started) do
      [%{id: id} | _rest] ->
        id

      [] when attempts > 0 ->
        Process.sleep(100)
        saved_recording(view, started, attempts - 1)
    end
  end

  # The replay renders in the player's frame, a page of its own.
  defp assert_frame(conn, check, attempts \\ 50) do
    evaluate(
      conn,
      ~s|document.querySelector("iframe")?.contentDocument?.body?.innerHTML ?? ""|,
      fn page ->
        send(self(), {:frame, page})
      end
    )

    receive do
      {:frame, page} ->
        cond do
          check.(page) ->
            conn

          attempts > 0 ->
            Process.sleep(200) && assert_frame(conn, check, attempts - 1)

          true ->
            flunk("The replay frame never showed it; it showed #{page}")
        end
    end
  end
end
