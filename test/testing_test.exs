defmodule PhoenixVapor.TestingTest do
  use ExUnit.Case, async: true

  import PhoenixVapor.Testing

  test "render_to_html renders a Rendered struct" do
    rendered = PhoenixVapor.render("<div>Hello {{ name }}</div>", %{name: "Ada"})

    assert render_to_html(rendered) == "<div>Hello Ada</div>"
  end

  test "static_values and dynamic_values expose rendered internals" do
    rendered = PhoenixVapor.render("<div>{{ name }}</div>", %{name: "Ada"})

    assert static_values(rendered) == ["<div>", "</div>"]
    assert dynamic_values(rendered) == ["Ada"]
  end
end
