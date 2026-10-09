defmodule VaporDemo.E2E.SessionReplayTest do
  # PhoenixReplay records a session, and its player replays it: PhoenixVapor
  # reports the client state the render reads, refs only the browser has, and
  # the replay renders with it, the package components it folded included.
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

  test "the replay of a recorded session shows the typed search and the delete dialog",
       %{conn: conn, started: started} do
    conn
    |> visit("/contacts")
    |> assert_has(".phx-connected")
    |> assert_has("[data-v-app]")
    |> type(~s(input[aria-label="Search contacts"]), "acme")
    |> assert_has("p", text: "3 of 12 contacts")
    |> reported(VaporDemoWeb.Workspace.ContactsLive, ~s(search "acme"))
    # The dialog is in a DialogPortal, which folds inline.
    |> click(~s(button[aria-label="Delete Dave Wilson"]))
    |> assert_has("[role=dialog]", text: "Delete contact?")
    |> reported(VaporDemoWeb.Workspace.ContactsLive, "deleteTarget %{")
    |> click_button("Cancel")
    # Leaving the page ends the recorded session, which is then saved.
    |> click_link("nav a", "Settings")
    |> assert_path("/settings")

    id = saved_recording(VaporDemoWeb.Workspace.ContactsLive, started)
    index = event(id, ~s(phoenix_vapor:pv-Contacts: search "acme"))

    conn
    |> visit("/dev/replay/#{id}?at=#{index}")
    |> assert_frame(fn page ->
      page =~ "3 of 12 contacts" and page =~ ~s(value="acme") and not (page =~ ~s(role="dialog"))
    end)
    |> visit("/dev/replay/#{id}?at=#{event(id, "deleteTarget %{")}")
    |> assert_frame(&(&1 =~ ~s(role="dialog") and &1 =~ "Delete contact?"))
  end

  test "the replay of a recorded session on /settings follows the tab, the filter, the dialog and the switches",
       %{conn: conn, started: started} do
    VaporDemo.Projects.reset()

    conn
    |> visit("/settings")
    |> assert_has(".phx-connected")
    |> assert_has("[data-v-app]")
    # Reka's tabs are role=tab, and switch on pointer down.
    # Changes within a second are reported together; each step waits for its
    # own report.
    |> click("[role=tab]", "Members")
    |> assert_has("p", text: "5 of 5 members")
    |> reported(~s(tab "members"))
    |> click("[role=combobox]")
    |> click("[role=option]", "Admin")
    |> assert_has("p", text: "2 of 5 members")
    |> reported(~s(roleFilter "admin"))
    |> click(~s[li:has-text("Bob Smith") button], "Remove")
    |> assert_has("[role=dialog]", text: "Bob Smith will lose access")
    |> reported("removeTarget %{")
    |> click_button("Cancel")
    |> reported("removeTarget nil")
    |> click("[role=tab]", "Notifications")
    |> reported(~s(tab "notifications"))
    |> click("#weekly-digest")
    |> assert_has(~s(#weekly-digest[aria-checked="true"]))
    |> reported("weeklyDigest true")
    |> click_link("nav a", "Contacts")
    |> assert_path("/contacts")

    id = saved_recording(VaporDemoWeb.Workspace.SettingsLive, started)
    key = "phoenix_vapor:pv-ProjectSettings"

    conn
    |> visit("/dev/replay/#{id}?at=#{event(id, ~s(#{key}: tab "members"))}")
    |> assert_frame(&(active_tab?(&1, "members") and &1 =~ "5 of 5 members"))
    |> visit("/dev/replay/#{id}?at=#{event(id, ~s(#{key}: roleFilter "admin"))}")
    |> assert_frame(
      &(active_tab?(&1, "members") and &1 =~ "2 of 5 members" and
          &1 =~ ~r/role="combobox"[^>]*>(<span[^>]*>)?Admin</ and not (&1 =~ ~s(role="dialog")))
    )
    |> visit("/dev/replay/#{id}?at=#{event(id, ~s(#{key}: removeTarget %{))}")
    |> assert_frame(&(&1 =~ ~s(role="dialog") and &1 =~ "Bob Smith will lose access"))
    |> visit("/dev/replay/#{id}?at=#{event(id, ~s(#{key}: weeklyDigest true))}")
    |> assert_frame(
      &(active_tab?(&1, "notifications") and
          &1 =~ ~r/<button[^>]*id="weekly-digest"[^>]*aria-checked="true"/ and
          &1 =~ ~r/<button[^>]*id="email-alerts"[^>]*aria-checked="true"/)
    )
  end

  # Waits for the view's running recording to have the client state report.
  defp reported(conn, view \\ VaporDemoWeb.Workspace.SettingsLive, label, attempts \\ 50) do
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

  # The folded tabs mark the active trigger.
  defp active_tab?(page, tab),
    do: page =~ ~r/<button[^>]*id="reka-tabs-[^"]*-trigger-#{tab}"[^>]*aria-selected="true"/

  # The index of the first recorded event whose label has `label`.
  defp event(id, label) do
    case Enum.find(Trace.events(id), &(&1.label =~ label)) do
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
