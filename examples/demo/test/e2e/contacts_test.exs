defmodule VaporDemo.E2E.ContactsTest do
  use PhoenixTest.Playwright.Case, async: false

  alias VaporDemo.Contacts

  @tag timeout: 30_000

  setup do
    Contacts.reset()
    :ok
  end

  defp hydrated(conn) do
    conn
    |> visit("/contacts")
    |> assert_has(".phx-connected")
    |> assert_has("[data-v-app]")
  end

  defp search(conn, text), do: fill_in(conn, "Search contacts", with: text)

  test "the server's first paint lists every contact, grouped by company", %{conn: conn} do
    conn
    |> visit("/contacts")
    |> assert_has("p", text: "12 of 12 contacts")
    |> assert_has("h2", text: "Acme Corp")
    |> assert_has("h2", text: "Pied Piper")
    |> assert_has("li", text: "LM")
    |> assert_has("li", text: "Leo Martinez")
  end

  test "search filters in the browser", %{conn: conn} do
    conn
    |> hydrated()
    |> search("hooli")
    |> assert_has("p", text: "2 of 12 contacts")
    |> assert_has("li", text: "Grace Lee")
    |> refute_has("li", text: "Bob Smith")
    |> click_button("Clear")
    |> assert_has("p", text: "12 of 12 contacts")
  end

  test "a search with no results shows the empty state", %{conn: conn} do
    conn
    |> hydrated()
    |> search("zzzz")
    |> assert_has("p", text: "0 of 12 contacts")
    |> assert_has("p", text: "No contacts match")
  end

  test "deleting through the dialog goes through the server", %{conn: conn} do
    conn
    |> hydrated()
    |> click_button("Delete Alice Chen")
    |> assert_has("[role=dialog]", text: "Alice Chen will be removed")
    |> within("[role=dialog]", &click_button(&1, "Delete"))
    |> assert_has("p", text: "11 of 11 contacts")
    |> refute_has("[role=dialog]")
    |> refute_has("li", text: "Alice Chen")
    # The browser's state carries on with the server's new props.
    |> search("hooli")
    |> assert_has("p", text: "2 of 11 contacts")

    assert length(Contacts.list()) == 11
  end

  test "deleting the selected contacts", %{conn: conn} do
    conn
    |> hydrated()
    |> search("globex")
    |> assert_has("p", text: "3 of 12 contacts")
    |> check("Select all")
    |> assert_has("span", text: "3 selected")
    |> click_button("Delete selected")
    |> assert_has("p", text: "0 of 9 contacts")
    |> refute_has("span", text: "3 selected")
  end

  test "a change made in another session reaches the open page", %{conn: conn} do
    conn =
      conn
      |> hydrated()
      |> search("a")
      |> assert_has("li", text: "Alice Chen")

    # Another session deletes Alice; PubSub brings the new list here.
    Contacts.delete([1])

    conn
    |> refute_has("li", text: "Alice Chen")
    |> assert_has("p", text: "of 11 contacts")
    # The search the browser holds is untouched.
    |> assert_has(~s(input[aria-label="Search contacts"]), value: "a")
  end
end
