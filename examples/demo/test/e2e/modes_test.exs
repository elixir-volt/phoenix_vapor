defmodule VaporDemo.E2E.ModesTest do
  use PhoenixTest.Playwright.Case, async: false

  @tag timeout: 30_000

  test "every page renders", %{conn: conn} do
    for path <-
          ~w(/ /modes/sigil /modes/server /modes/reactive /modes/hybrid /modes/full /modes/compare) do
      conn |> visit(path) |> assert_has("main h1")
    end
  end

  # The test environment sets data-vapor-debug, so patchLiveSocket counts the
  # updates it writes straight to the DOM in window.__vaporDirectPatches.
  test "reactive mode patches value-only diffs directly", %{conn: conn} do
    conn
    |> visit("/modes/reactive")
    # Clicks before the socket joins are lost.
    |> assert_has(".phx-connected")
    |> assert_has("[data-vapor-statics]")
    |> assert_has("p", text: "Doubled: 0")
    |> click_button("+")
    |> assert_has("p", text: "Doubled: 2")
    |> click_button("+")
    |> assert_has("p", text: "Doubled: 4 · Positive")
    |> evaluate("window.__vaporDirectPatches", &assert(&1 > 0))
  end

  test "hybrid mode counts in the browser and saves on the server", %{conn: conn} do
    conn
    |> visit("/modes/hybrid")
    |> assert_has(".phx-connected")
    |> assert_has("[data-v-app]")
    |> click_button("+")
    |> click_button("+")
    |> click_button("+")
    |> assert_has("p.font-mono", text: "3")
    |> assert_has("p", text: "Saved on the server: 0")
    |> click_button("Save")
    |> assert_has("p", text: "Saved on the server: 3")
  end

  test "hybrid mode takes back a change the server declines", %{conn: conn} do
    conn
    |> visit("/modes/hybrid")
    |> assert_has(".phx-connected")
    |> assert_has("[data-v-app]")
    |> click_button("−")
    |> click_button("Save")
    |> assert_has("[role=alert]", text: "A count below zero isn't saved.")
    # The browser showed -1 at once; the server left `saved` at 0.
    |> assert_has("p", text: "Saved on the server: 0")
  end
end
