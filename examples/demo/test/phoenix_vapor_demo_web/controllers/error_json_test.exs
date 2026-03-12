defmodule PhoenixVaporDemoWeb.ErrorJSONTest do
  use PhoenixVaporDemoWeb.ConnCase, async: true

  test "renders 404" do
    assert PhoenixVaporDemoWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert PhoenixVaporDemoWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
