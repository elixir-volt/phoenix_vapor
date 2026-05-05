defmodule VaporDemo.E2E.HybridContactsTest do
  use PhoenixTest.Playwright.Case, async: false

  @tag timeout: 30_000

  defp type_search(conn, text) do
    conn
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
    |> assert_has("text=Alice Chen")
    |> assert_has("text=Bob Smith")
    |> assert_has("text=Leo Martinez")
  end

  test "shows contact count", %{conn: conn} do
    conn
    |> visit("/search")
    |> assert_has("text=12 of 12 contacts")
  end

  test "instant search filters contacts", %{conn: conn} do
    conn
    |> visit("/search")
    |> assert_has("text=12 of 12 contacts")
    |> type_search("alice")
    |> assert_has("text=1 of 12 contacts")
    |> assert_has("text=Alice Chen")
    |> refute_has("text=Bob Smith")
  end

  test "clearing search shows all contacts again", %{conn: conn} do
    conn
    |> visit("/search")
    |> type_search("grace")
    |> assert_has("text=1 of 12 contacts")
    |> click_button("Clear")
    |> assert_has("text=12 of 12 contacts")
  end

  test "search by company", %{conn: conn} do
    conn
    |> visit("/search")
    |> type_search("hooli")
    |> assert_has("text=2 of 12 contacts")
    |> assert_has("text=Grace Lee")
    |> assert_has("text=Iris Wang")
  end

  test "search with no results shows empty state", %{conn: conn} do
    conn
    |> visit("/search")
    |> type_search("zzzznonexistent")
    |> assert_has("text=0 of 12 contacts")
    |> assert_has("text=No contacts match")
  end
end
