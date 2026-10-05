defmodule VaporDemo.E2E.SettingsTest do
  use PhoenixTest.Playwright.Case, async: false

  alias VaporDemo.Projects

  @tag timeout: 30_000

  setup do
    Projects.reset()
    :ok
  end

  defp hydrated(conn) do
    conn
    |> visit("/settings")
    |> assert_has(".phx-connected")
    |> assert_has("[data-v-app]")
  end

  test "renaming the project goes through the server", %{conn: conn} do
    conn
    |> hydrated()
    |> assert_has("h2", text: "Acme Dashboard")
    |> fill_in("Project name", with: "Acme Console")
    |> click_button("Save")
    |> assert_has("h2", text: "Acme Console")

    assert Projects.project().name == "Acme Console"
  end

  test "a member removed in another session disappears here", %{conn: conn} do
    conn =
      conn
      |> hydrated()
      # Reka's tabs are role=tab, and switch on pointer down.
      |> click("[role=tab]", "Members")
      |> assert_has("li", text: "Dave Wilson")

    Projects.remove_member(4)

    refute_has(conn, "li", text: "Dave Wilson")
  end
end
