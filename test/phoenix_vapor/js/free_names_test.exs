defmodule PhoenixVapor.JS.FreeNamesTest do
  use ExUnit.Case, async: true

  alias PhoenixVapor.JS.FreeNames

  defp names(source, opts \\ []) do
    {:ok, ast} = OXC.parse(source, "e.js")
    FreeNames.of(ast, opts)
  end

  test "property names and labels aren't names" do
    assert names("user.name + items[i] + ({ a: b, [c]: d, e })") == ~w(user items i b c d e)
    assert names("outer: for (;;) { break outer }") == []
  end

  test "function parameters, including patterns and defaults, are bound in the body" do
    assert names("items.map((item, i) => item.id + i + offset)") == ~w(items offset)

    assert names("({ a, b: [c], ...rest } = {}, d = a + fallback) => a + c + d + rest + x") ==
             ~w(fallback x)

    assert names("function f(n) { return n > 0 ? f(n - 1) : limit }") == ~w(limit)
  end

  test "declarations are in scope in their block, catch parameters in theirs" do
    assert names("{ const total = price * qty; log(total) }") == ~w(price qty log)
    assert names("for (const row of rows) { sum += row.amount }") == ~w(rows sum)
    assert names("try { run() } catch (error) { report(error) }") == ~w(run report)
    assert names("{ let shadow = 1 } shadow") == ~w(shadow)
  end

  test "props.x is reported as such on request" do
    assert names("props.tone + size", props: true) == ~w(props.tone size)
    assert names("props.tone + size") == ~w(props size)
    assert names("(props) => props.tone", props: true) == []
  end

  test "occurrences are each free use of a name, with where it starts" do
    source = "function clear(users) { users = [] }\nusers = users.filter(f)"
    {:ok, ast} = OXC.parse(source, "e.js")

    # The parameter's write is bound; the second line's two uses aren't.
    assert FreeNames.occurrences(ast) == [{"users", 37}, {"users", 45}, {"f", 58}]
  end
end
