defmodule VaporDemo.E2E.HybridContactsTest do
  use PhoenixTest.Playwright.Case, async: false

  @tag timeout: 30_000

  defp type_search(conn, text) do
    conn
    |> assert_has("[data-v-app]")
    |> evaluate("""
      const input = document.querySelector('[placeholder="Search contacts..."]');
      if (input) {
        const nativeInputValueSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
        nativeInputValueSetter.call(input, '#{text}');
        input.dispatchEvent(new Event('input', { bubbles: true }));
      }
    """)
  end

  test "renders all 12 contacts on initial load", %{conn: conn} do
    conn
    |> visit("/search")
    |> assert_has("body", text: "Alice Chen")
    |> assert_has("body", text: "Bob Smith")
    |> assert_has("body", text: "Leo Martinez")
  end

  test "shows contact count", %{conn: conn} do
    conn
    |> visit("/search")
    |> assert_has("body", text: "12 of 12 contacts")
  end

  test "instant search filters contacts", %{conn: conn} do
    conn
    |> visit("/search")
    |> assert_has("body", text: "12 of 12 contacts")
    |> type_search("alice")
    |> assert_has("body", text: "1 of 12 contacts")
    |> assert_has("body", text: "Alice Chen")
    |> refute_has("body", text: "Bob Smith")
  end

  test "clearing search shows all contacts again", %{conn: conn} do
    conn
    |> visit("/search")
    |> type_search("grace")
    |> assert_has("body", text: "1 of 12 contacts")
    |> click_button("Clear")
    |> assert_has("body", text: "12 of 12 contacts")
  end

  test "search by company", %{conn: conn} do
    conn
    |> visit("/search")
    |> type_search("hooli")
    |> assert_has("body", text: "2 of 12 contacts")
    |> assert_has("body", text: "Grace Lee")
    |> assert_has("body", text: "Iris Wang")
  end

  test "search with no results shows empty state", %{conn: conn} do
    conn
    |> visit("/search")
    |> type_search("zzzznonexistent")
    |> assert_has("body", text: "0 of 12 contacts")
    |> assert_has("body", text: "No contacts match")
  end
end
