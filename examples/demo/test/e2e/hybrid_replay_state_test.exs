defmodule VaporDemo.E2E.HybridReplayStateTest do
  # The board reports the client state its render reads while a session is
  # recorded, through `replay_recorder.ts`, which stands in for PhoenixReplay.
  use PhoenixTest.Playwright.Case, async: false

  alias VaporDemo.E2E.ReplayRecorder

  @tag timeout: 30_000

  @key "phoenix_vapor:pv-Board"

  setup do
    VaporDemo.Tracker.reset()
    :ok
  end

  defp board(conn) do
    conn
    |> visit("/engineering/board")
    |> assert_has(".phx-connected")
    |> assert_has("[data-v-app]")
    |> ReplayRecorder.install()
  end

  # The board's reports; the palette, on every page, reports its own.
  defp board_reports(conn, fun),
    do:
      ReplayRecorder.reports(conn, &fun.(Enum.filter(&1, fn report -> report["key"] == @key end)))

  defp filter(conn, menu, value) do
    conn
    |> click("button", "#{menu}:")
    |> click("[role=menuitemradio]", value)
    |> assert_has("button", text: "#{menu}: #{value}")
  end

  test "reports the client state the render reads, only while recorded, then coalesced changes",
       %{conn: conn} do
    conn
    |> board()
    # Nothing goes out before recording starts, even when state changes.
    |> filter("Priority", "High")
    |> board_reports(&assert(&1 == []))
    # Nor for a recording without client state.
    |> ReplayRecorder.start(nil)
    |> board_reports(&assert(&1 == []))
    # On start, all of the state the server render reads.
    |> ReplayRecorder.start(%{flush: 50})
    |> board_reports(fn reports ->
      assert [%{"changes" => changes}] = reports

      assert changes == %{
               "assignee" => "anyone",
               "dragging" => nil,
               "over" => nil,
               "priority" => "high"
             }
    end)
    # Then only what changed, with its latest value.
    |> filter("Assignee", "Me")
    |> board_reports(fn reports ->
      assert [_start, %{"changes" => changes}] = reports
      assert changes == %{"assignee" => "me"}
    end)
    # After stop, nothing.
    |> ReplayRecorder.stop()
    |> filter("Priority", "Low")
    |> board_reports(&assert(length(&1) == 2))
  end

  test "a change waiting for the next flush goes out when the page is hidden", %{conn: conn} do
    conn
    |> board()
    |> ReplayRecorder.start(%{flush: 60_000})
    |> filter("Priority", "Urgent")
    # The change waits for the flush interval.
    |> board_reports(&assert(length(&1) == 1))
    |> ReplayRecorder.hide()
    |> board_reports(fn reports ->
      assert [_start, %{"changes" => %{"priority" => "urgent"}}] = reports
    end)
  end

  test "a component that mounts during a recording reports its state then", %{conn: conn} do
    conn
    |> visit("/engineering/issues")
    |> assert_has(".phx-connected")
    |> ReplayRecorder.install()
    # Recording started before this component, or before the bridge loaded:
    # only the attribute on <html> says so.
    |> ReplayRecorder.mark_recording(%{flush: 50})
    |> click_link("nav[aria-label=Engineering] a", "Board")
    |> assert_has("[data-status=todo]")
    |> board_reports(fn reports ->
      assert %{"changes" => changes} = List.last(reports)
      assert Map.keys(changes) == ~w(assignee dragging over priority)
    end)
  end
end
