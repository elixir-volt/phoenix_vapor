defmodule VaporDemo.E2E.SessionReplayTest do
  # PhoenixReplay records a session on /contacts, and its player replays it:
  # PhoenixVapor reports the search, a ref only the browser has, and the
  # replay renders the list filtered by it.
  use PhoenixTest.Playwright.Case, async: false

  alias PhoenixReplay.Trace

  @tag timeout: 60_000

  setup do
    VaporDemo.Contacts.reset()

    # Recording is off in tests; this one records.
    previous = Application.get_env(:phoenix_replay, :sample_rate)
    Application.put_env(:phoenix_replay, :sample_rate, 1.0)
    on_exit(fn -> Application.put_env(:phoenix_replay, :sample_rate, previous) end)

    %{started: DateTime.utc_now()}
  end

  test "the replay of a recorded session shows the typed search", %{conn: conn, started: started} do
    conn
    |> visit("/contacts")
    |> assert_has(".phx-connected")
    |> assert_has("[data-v-app]")
    |> type(~s(input[aria-label="Search contacts"]), "acme")
    |> assert_has("p", text: "3 of 12 contacts")
    # Leaving the page ends the recorded session, which is then saved.
    |> click_link("nav a", "Settings")
    |> assert_path("/settings")

    id = saved_recording(started)

    %{index: index} =
      id
      |> Trace.events()
      |> Enum.find(&(&1.label =~ ~s(phoenix_vapor:pv-Contacts: search "acme")))

    conn
    |> visit("/dev/replay/#{id}?at=#{index}")
    |> assert_frame(fn page -> page =~ "3 of 12 contacts" and page =~ ~s(value="acme") end)
  end

  defp saved_recording(started, attempts \\ 50) do
    case Trace.find(view: VaporDemoWeb.Workspace.ContactsLive, live: false, from: started) do
      [%{id: id} | _rest] ->
        id

      [] when attempts > 0 ->
        Process.sleep(100)
        saved_recording(started, attempts - 1)
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
            flunk(
              "The replay frame never showed it; it showed #{inspect(Regex.run(~r/\d+ of \d+ contacts/, page))}"
            )
        end
    end
  end
end
