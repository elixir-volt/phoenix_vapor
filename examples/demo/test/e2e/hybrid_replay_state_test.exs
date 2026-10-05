defmodule VaporDemo.E2E.HybridReplayStateTest do
  use PhoenixTest.Playwright.Case, async: false

  @tag timeout: 30_000

  # A session replayer such as PhoenixReplay starts recording with a
  # `phx_replay:start` window event, its client-state settings as the detail,
  # and collects `phx_replay:state` reports. This collects them itself, and
  # puts what it saw on the body to assert on, after the flush interval.
  @collect """
  window.__pvStates = []
  window.addEventListener("phx_replay:state", (e) => window.__pvStates.push(e.detail))
  """

  @expose """
  (async () => {
    await new Promise((resolve) => setTimeout(resolve, 150))
    const last = window.__pvStates.at(-1)
    document.body.dataset.states = String(window.__pvStates.length)
    document.body.dataset.key = last ? last.key : ""
    document.body.dataset.changes = last ? Object.keys(last.changes).sort().join(",") : ""
    document.body.dataset.search = last && "search" in last.changes ? last.changes.search : ""
  })()
  """

  @start ~s|window.dispatchEvent(new CustomEvent("phx_replay:start", {detail: {state: {flush: 50}}}))|

  # Types into the search box the way a user does, one input event per key.
  defp type(conn, text) do
    evaluate(conn, """
    const input = document.querySelector("input[type=search], input[placeholder*=Search]")
    for (const char of #{Jason.encode!(text)}) {
      input.value += char
      input.dispatchEvent(new Event("input", { bubbles: true }))
    }
    """)
  end

  test "reports the client state the render reads, only while recorded, then coalesced changes",
       %{conn: conn} do
    conn
    |> visit("/contacts")
    |> assert_has(".phx-connected")
    |> assert_has("[data-v-app]")
    |> evaluate(@collect)
    # Nothing goes out before recording starts, even when state changes.
    |> type("a")
    |> evaluate(@expose)
    |> assert_has(~s|body[data-states="0"]|)
    # A start without client state reports nothing either.
    |> evaluate(
      ~s|window.dispatchEvent(new CustomEvent("phx_replay:start", {detail: {state: null}}))|
    )
    |> evaluate(@expose)
    |> assert_has(~s|body[data-states="0"]|)
    # On start, all of the state the server render reads.
    |> evaluate(@start)
    |> evaluate(@expose)
    |> assert_has(~s|body[data-states="1"][data-key="phoenix_vapor:pv-HybridContacts"]|)
    |> assert_has(~s|body[data-changes="search,selectedIds,sortKey"][data-search="a"]|)
    # Typing three more characters within one flush is one report, of only
    # the search, with its latest value.
    |> type("li")
    |> evaluate(@expose)
    |> assert_has(~s|body[data-states="2"][data-changes="search"][data-search="ali"]|)
    # After stop, nothing.
    |> evaluate(~s|window.dispatchEvent(new CustomEvent("phx_replay:stop"))|)
    |> type("c")
    |> evaluate(@expose)
    |> assert_has(~s|body[data-states="2"]|)
  end

  test "a component that mounts during a recording reports its state then", %{conn: conn} do
    conn
    |> visit("/playground/hybrid")
    |> assert_has(".phx-connected")
    |> assert_has("[data-v-app]")
    |> evaluate(@collect)
    # Recording started before this component, or before the bridge loaded:
    # only the attribute on <html> says so.
    |> evaluate(
      ~s|document.documentElement.dataset.phxReplay = JSON.stringify({state: {flush: 50}})|
    )
    |> evaluate(
      ~s|liveSocket.execJS(document.body, JSON.stringify([["navigate", {href: "/contacts"}]]))|
    )
    |> assert_has("h1", text: "Contacts")
    |> evaluate(@expose)
    |> assert_has(~s|body[data-key="phoenix_vapor:pv-HybridContacts"]|)
    |> assert_has(~s|body[data-changes="search,selectedIds,sortKey"]|)
  end
end
