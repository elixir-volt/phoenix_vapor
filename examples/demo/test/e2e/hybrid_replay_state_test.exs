defmodule VaporDemo.E2E.HybridReplayStateTest do
  use PhoenixTest.Playwright.Case, async: false

  @tag timeout: 30_000

  # A session replayer such as PhoenixReplay starts recording with a
  # `phx_replay:start` window event and collects `phx_replay:state` reports.
  # This collects them itself, and puts what it saw on the body to assert on.
  @collect """
  window.__pvStates = []
  window.addEventListener("phx_replay:state", (e) => window.__pvStates.push(e.detail))
  """

  @expose """
  document.body.dataset.states = String(window.__pvStates.length)
  const last = window.__pvStates.at(-1)
  document.body.dataset.key = last ? last.key : ""
  document.body.dataset.changes = last ? Object.keys(last.changes).sort().join(",") : ""
  document.body.dataset.tab = last && "tab" in last.changes ? last.changes.tab : ""
  """

  test "reports a hybrid component's refs only while recorded, then only what changed",
       %{conn: conn} do
    conn
    |> visit("/playground/hybrid")
    |> assert_has(".phx-connected")
    |> assert_has("[data-v-app]")
    |> evaluate(@collect)
    # Nothing goes out before recording starts, even when refs change.
    |> click("[role=tab]", "Members")
    |> evaluate(@expose)
    |> assert_has(~s|body[data-states="0"]|)
    # A start without client state reports nothing either.
    |> evaluate(
      ~s|window.dispatchEvent(new CustomEvent("phx_replay:start", {detail: {state: null}}))|
    )
    |> evaluate(@expose)
    |> assert_has(~s|body[data-states="0"]|)
    # On start, all of the component's refs.
    |> evaluate(
      ~s|window.dispatchEvent(new CustomEvent("phx_replay:start", {detail: {state: {}}}))|
    )
    |> evaluate(@expose)
    |> assert_has(
      ~s|body[data-states="1"][data-key="phoenix_vapor:pv-ProjectSettings"][data-tab="members"]|
    )
    |> assert_has(
      ~s|body[data-changes="emailAlerts,name,removeTarget,roleFilter,tab,weeklyDigest"]|
    )
    # Then only the refs that changed.
    |> click("[role=tab]", "General")
    |> evaluate(@expose)
    |> assert_has(~s|body[data-states="2"][data-changes="tab"][data-tab="general"]|)
    # After stop, nothing.
    |> evaluate(~s|window.dispatchEvent(new CustomEvent("phx_replay:stop"))|)
    |> click("[role=tab]", "Members")
    |> evaluate(@expose)
    |> assert_has(~s|body[data-states="2"]|)
  end
end
