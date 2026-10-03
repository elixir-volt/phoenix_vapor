defmodule VaporDemo.E2E.HybridServerActionsTest do
  use PhoenixTest.Playwright.Case, async: false

  @tag timeout: 30_000

  defp type_into(conn, placeholder, text) do
    evaluate(conn, """
      const input = document.querySelector('[placeholder="#{placeholder}"]');
      const setValue = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
      setValue.call(input, '#{text}');
      input.dispatchEvent(new Event('input', { bubbles: true }));
    """)
  end

  defp click_first(conn, selector) do
    evaluate(conn, "document.querySelector('#{selector}').click()")
  end

  test "a server action removes the user and the client stays interactive", %{conn: conn} do
    conn
    |> visit("/hybrid")
    |> assert_has("[data-v-app]")
    |> assert_has("body", text: "8 of 8 users shown")
    |> click_first("li button")
    |> assert_has("body", text: "7 of 7 users shown")
    |> refute_has("body", text: "Alice Chen")
    # The server's new props reach the wrapper without replacing Vue's DOM.
    |> assert_has(~s|[data-pv-props]:not([data-pv-props*="Alice"])|)
    |> type_into("Filter users...", "bob")
    |> assert_has("body", text: "1 of 7 users shown")
  end

  test "deleting a contact through the Reka dialog", %{conn: conn} do
    conn
    |> visit("/contacts")
    |> assert_has("[data-v-app]")
    |> assert_has("body", text: "12 of 12 contacts")
    |> click_first("button.p-1\\\\.5")
    |> assert_has("body", text: "Delete contact?")
    |> click_button("Delete")
    |> assert_has("body", text: "11 of 11 contacts")
    |> assert_has(~s|[data-pv-props]:not([data-pv-props*="Alice Chen"])|)
    |> type_into("Search contacts...", "hooli")
    |> assert_has("body", text: "2 of 11 contacts")
  end
end
