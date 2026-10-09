defmodule VaporDemo.E2E.TrackerTest do
  # The tracker as a visitor uses it, in a browser: the board, the issue
  # page, the list, the reactive new-issue form, the palette and the x-ray.
  use PhoenixTest.Playwright.Case, async: false

  alias VaporDemo.Tracker

  @tag timeout: 60_000

  setup do
    Tracker.reset()
    :ok
  end

  defp hydrated(conn, path) do
    conn
    |> visit(path)
    |> assert_has(".phx-connected")
    |> assert_has("[data-v-app]")
  end

  defp column(issue_key) do
    issue = Tracker.issue(issue_key)
    issue.status
  end

  test "dragging a card moves the issue through the server", %{conn: conn} do
    conn
    |> hydrated("/engineering/board")
    |> drag(~s([data-issue="ENG-151"]), to: ~s([data-status="todo"]))
    |> assert_has(~s([data-status="todo"] [data-issue="ENG-151"]))
    |> assert_has("aside[aria-label=Activity] li", text: "moved ENG-151 to Todo")

    assert column("ENG-151") == "todo"
  end

  test "a move made elsewhere reaches an open board", %{conn: conn} do
    conn = hydrated(conn, "/engineering/board")
    Tracker.move(Tracker.issue("ENG-150").id, "done")
    assert_has(conn, ~s([data-status="done"] [data-issue="ENG-150"]))
  end

  test "the board's filters run in the browser", %{conn: conn} do
    conn
    |> hydrated("/engineering/board")
    |> click("button", "Priority:")
    |> click("[role=menuitemradio]", "Urgent")
    |> assert_has("button", text: "Priority: Urgent")
    |> assert_has("[data-issue=ENG-142]")
    |> refute_has("[data-issue=ENG-151]")
  end

  test "the issue page saves edits, properties and comments through the server", %{conn: conn} do
    conn
    |> hydrated("/issue/ENG-142")
    |> click("button", "Status")
    |> click("[role=menuitem]", "In Review")
    |> assert_has("button", text: "In Review")
    |> fill_in("Title", with: "Keep the path and params after sign-in")
    |> press("#issue-title", "Enter")
    |> fill_in("Comment", with: "Fixed, with a test.")
    |> click_button("Comment")
    |> assert_has("article", text: "Fixed, with a test.")

    issue = Tracker.issue("ENG-142")
    assert issue.status == "in_review"
    assert issue.title == "Keep the path and params after sign-in"
    assert [_, _, %{body: "Fixed, with a test."}] = Tracker.comments(issue.id)
  end

  test "the list moves a selection at once", %{conn: conn} do
    conn
    |> hydrated("/engineering/issues")
    |> check("Select ENG-151")
    |> check("Select ENG-150")
    |> assert_has("div", text: "2 selected")
    |> click("button", "Move to…")
    |> click("[role=menuitem]", "Done")
    |> refute_has("div", text: "2 selected")

    assert column("ENG-151") == "done"
    assert column("ENG-150") == "done"
  end

  test "the new issue form runs on the server and creates the issue", %{conn: conn} do
    conn
    |> visit("/new")
    |> assert_has(".phx-connected")
    |> type("#new-title", "Show shortcuts in menus")
    # The count follows a v-if; it's patched in place, in the right element.
    |> assert_has("span", text: "23/80")
    |> assert_has("span", text: "A short sentence; the description holds the rest.")
    |> assert_has("code", text: "alice/eng-new-show-shortcuts-in-menus")
    # Those were value-only updates, written straight to the DOM.
    |> evaluate("window.__vaporDirectPatches ?? 0", &assert(&1 > 0))
    |> click("label", "High")
    |> click_button("Create issue")
    |> assert_path("/issue/ENG-152")

    assert %{title: "Show shortcuts in menus", priority: "high"} = Tracker.issue("ENG-152")
  end

  test "the palette finds an issue and opens it", %{conn: conn} do
    conn
    |> hydrated("/engineering/board")
    |> click("button", "Search or jump to")
    |> type("input[aria-label='Search commands and issues']", "webhook")
    |> assert_has("[role=dialog] a", text: "Retry webhooks with backoff")
    |> press("input[aria-label='Search commands and issues']", "Enter")
    |> assert_path("/issue/ENG-145")
  end

  test "the x-ray outlines the regions and shows a region's source", %{conn: conn} do
    conn
    |> hydrated("/engineering/board")
    |> click("button", "X-ray")
    |> assert_has("aside", text: "How this page renders")
    |> click(~s([data-issue="ENG-142"]))
    |> assert_has("#xray-source code", text: "lib/vapor_demo_web/board/Board.vue")
    |> assert_has("#xray-source pre", text: "const issues = defineModel")
    |> assert_path("/engineering/board")
  end
end
