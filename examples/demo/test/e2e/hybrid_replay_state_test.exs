defmodule VaporDemo.E2E.HybridReplayStateTest do
  use PhoenixTest.Playwright.Case, async: false

  alias VaporDemo.E2E.ReplayRecorder

  @tag timeout: 30_000

  @key "phoenix_vapor:pv-Contacts"
  @search ~s(input[aria-label="Search contacts"])

  setup do
    VaporDemo.Contacts.reset()
    :ok
  end

  defp contacts(conn) do
    conn
    |> visit("/contacts")
    |> assert_has(".phx-connected")
    |> assert_has("[data-v-app]")
    |> ReplayRecorder.install()
  end

  test "reports the client state the render reads, only while recorded, then coalesced changes",
       %{conn: conn} do
    conn
    |> contacts()
    # Nothing goes out before recording starts, even when state changes.
    |> type(@search, "a")
    |> ReplayRecorder.reports(&assert(&1 == []))
    # Nor for a recording without client state.
    |> ReplayRecorder.start(nil)
    |> ReplayRecorder.reports(&assert(&1 == []))
    # On start, all of the state the server render reads.
    |> ReplayRecorder.start(%{flush: 50})
    |> ReplayRecorder.reports(fn reports ->
      assert [%{"key" => @key, "changes" => changes}] = reports

      assert changes == %{
               "copied" => false,
               "search" => "a",
               "selectedIds" => [],
               "sortKey" => "name"
             }
    end)
    # Two keys within one flush are one report, of only the search, with its
    # latest value.
    |> type(@search, "li")
    |> ReplayRecorder.reports(fn reports ->
      assert [_start, %{"key" => @key, "changes" => changes}] = reports
      assert changes == %{"search" => "ali"}
    end)
    # After stop, nothing.
    |> ReplayRecorder.stop()
    |> type(@search, "c")
    |> ReplayRecorder.reports(&assert(length(&1) == 2))
  end

  test "a change waiting for the next flush goes out when the page is hidden", %{conn: conn} do
    conn
    |> contacts()
    |> ReplayRecorder.start(%{flush: 60_000})
    |> type(@search, "bo")
    # The change waits for the flush interval.
    |> ReplayRecorder.reports(&assert(length(&1) == 1))
    |> ReplayRecorder.hide()
    |> ReplayRecorder.reports(fn reports ->
      assert [_start, %{"changes" => %{"search" => "bo"}}] = reports
    end)
  end

  test "a component that mounts during a recording reports its state then", %{conn: conn} do
    conn
    |> visit("/settings")
    |> assert_has(".phx-connected")
    |> ReplayRecorder.install()
    # Recording started before this component, or before the bridge loaded:
    # only the attribute on <html> says so.
    |> ReplayRecorder.mark_recording(%{flush: 50})
    |> click_link("nav a", "Contacts")
    |> assert_has("h1", text: "Contacts")
    |> ReplayRecorder.reports(fn reports ->
      assert %{"key" => @key, "changes" => changes} = List.last(reports)
      assert Map.keys(changes) == ~w(copied search selectedIds sortKey)
    end)
  end
end
