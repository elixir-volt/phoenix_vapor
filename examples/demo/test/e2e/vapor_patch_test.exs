defmodule VaporDemo.E2E.VaporPatchTest do
  use PhoenixTest.Playwright.Case, async: false

  @tag timeout: 30_000

  # The demo calls patchLiveSocket(liveSocket, {debug: true}), which counts
  # updates written straight to the DOM in window.__vaporDirectPatches.
  test "value-only diffs are patched directly", %{conn: conn} do
    conn
    |> visit("/reactive")
    # Clicks before the socket joins are lost.
    |> assert_has(".phx-connected")
    |> assert_has("[data-vapor-statics]")
    |> assert_has("p", text: "Doubled: 0")
    |> click_button("+")
    |> assert_has("p", text: "Doubled: 2")
    |> click_button("+")
    |> assert_has("p", text: "Doubled: 4")
    |> evaluate("document.body.dataset.vaporPatches = String(window.__vaporDirectPatches ?? 0)")
    |> assert_has(~s|body[data-vapor-patches]:not([data-vapor-patches="0"])|)
  end
end
