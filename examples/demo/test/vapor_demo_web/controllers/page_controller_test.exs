defmodule VaporDemoWeb.PageControllerTest do
  use VaporDemoWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Phoenix Vapor"
  end
end
