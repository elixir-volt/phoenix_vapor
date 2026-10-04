defmodule PhoenixVapor.ExprTest do
  use ExUnit.Case, async: true

  alias PhoenixVapor.Renderer.Expr

  describe "eval/2" do
    test "resolves identifiers and nested access" do
      assert Expr.eval("msg", %{msg: "hello"}) == "hello"
      assert Expr.eval("user.name", %{user: %{name: "Dan"}}) == "Dan"

      assigns = %{user: %{address: %{city: "Moscow"}}}
      assert Expr.eval("user.address.city", assigns) == "Moscow"
    end

    test "supports atom and string keys" do
      assert Expr.eval("x", %{x: 1}) == 1
      assert Expr.eval("x", %{"x" => 2}) == 2
    end

    test "returns nil for missing keys" do
      assert Expr.eval("missing", %{}) == nil
    end

    test "passes static expressions through" do
      assert Expr.eval({:static_, "hello"}, %{}) == "hello"
    end

    test "evaluates literals" do
      assert Expr.eval("true", %{}) == true
      assert Expr.eval("false", %{}) == false
      assert Expr.eval("null", %{}) == nil
    end

    test "evaluates conditional expressions" do
      assert Expr.eval(~s[ok ? "y" : "n"], %{ok: true}) == "y"
      assert Expr.eval(~s[ok ? "y" : "n"], %{ok: false}) == "n"
    end

    test "evaluates arithmetic and comparisons" do
      assert Expr.eval("a + b", %{a: 2, b: 3}) == 5
      assert Expr.eval("a - b", %{a: 10, b: 3}) == 7
      assert Expr.eval("a * b", %{a: 4, b: 5}) == 20
      assert Expr.eval("a > b", %{a: 5, b: 3}) == true
      assert Expr.eval("a === b", %{a: 1, b: 1}) == true
      assert Expr.eval("a !== b", %{a: 1, b: 2}) == true
    end

    test "evaluates logical expressions" do
      assert Expr.eval("a && b", %{a: true, b: "yes"}) == "yes"
      assert Expr.eval("a && b", %{a: false, b: "yes"}) == false
      assert Expr.eval("a || b", %{a: nil, b: "fallback"}) == "fallback"
      assert Expr.eval("a ?? b", %{a: nil, b: "default"}) == "default"
      assert Expr.eval("a ?? b", %{a: 0, b: "default"}) == 0
    end

    test "evaluates unary expressions" do
      assert Expr.eval("!x", %{x: false}) == true
      assert Expr.eval("-x", %{x: 5}) == -5
    end

    test "evaluates member and array access" do
      assert Expr.eval("items.length", %{items: [1, 2, 3]}) == 3
      assert Expr.eval("items[1]", %{items: ["a", "b", "c"]}) == "b"
    end

    test "evaluates typeof" do
      assert Expr.eval("typeof x", %{x: 42}) == "number"
      assert Expr.eval("typeof x", %{x: "hi"}) == "string"
      # `nil` is `null`, whose type is "object"; a missing name is `undefined`.
      assert Expr.eval("typeof x", %{x: nil}) == "object"
      assert Expr.eval("typeof x", %{}) == "undefined"
    end

    test "evaluates string and array methods" do
      assert Expr.eval(~s[s.trim()], %{s: "  hi  "}) == "hi"
      assert Expr.eval(~s[s.toUpperCase()], %{s: "hi"}) == "HI"
      assert Expr.eval(~s[s.toLowerCase()], %{s: "HI"}) == "hi"

      assigns = %{items: ["a", "b", "c"]}
      assert Expr.eval(~s[items.includes("b")], assigns) == true
      assert Expr.eval(~s[items.includes("z")], assigns) == false
    end
  end

  describe "eval_values/2" do
    test "concatenates values" do
      values = [{:static_, "Hello "}, "name", {:static_, "!"}]
      assert Expr.eval_values(values, %{name: "World"}) == "Hello World!"
    end
  end

  describe "assign_keys/1" do
    test "extracts identifiers" do
      assert Expr.assign_keys("msg") == ["msg"]
      assert "user" in Expr.assign_keys("user.name")
      assert Expr.assign_keys({:static_, "text"}) == []
    end

    test "extracts identifiers from complex expressions" do
      keys = Expr.assign_keys("a > b ? x : y")
      assert "a" in keys
      assert "b" in keys
      assert "x" in keys
      assert "y" in keys
    end
  end

  describe "JavaScript semantics" do
    defp js(source, assigns), do: source |> Expr.compile() |> Expr.eval(assigns)

    test "truthiness follows JavaScript" do
      assert js(~s(count ? "yes" : "no"), %{count: 0}) == "no"
      assert js(~s(count ? "yes" : "no"), %{count: 0.0}) == "no"
      assert js("!name", %{name: ""}) == true
      assert js(~s(label || "fallback"), %{label: ""}) == "fallback"
      assert js(~s(items && items.length), %{items: []}) == 0
      assert js(~s(x ?? "default"), %{}) == "default"
      assert js(~s(x ?? "default"), %{x: 0}) == 0
    end

    test "comparisons convert as JavaScript does" do
      # `undefined > 0` is false, though Elixir orders atoms after numbers.
      assert js("items.length > 0", %{}) == false
      assert js("count > 0", %{count: nil}) == false
      assert js("count === 1", %{count: 1.0}) == true
      assert js(~s(count == "1"), %{count: 1}) == true
      assert js(~s(count === "1"), %{count: 1}) == false
      assert js("x == null", %{}) == true
      assert js(~s("b" > "a"), %{}) == true
      assert js(~s("10" < 9), %{}) == false
    end

    test "arithmetic and concatenation convert as JavaScript does" do
      assert js("a + b", %{a: "1", b: 2}) == "12"
      assert js("a + b", %{a: 1, b: 2}) == 3
      assert js("n + 1", %{n: nil}) == 1
      assert js("n + 1", %{}) == :nan
      assert js("1 / 0", %{}) == :infinity
      assert js(~s("x" * 2), %{}) == :nan
      assert js("`${a}-${b}`", %{a: 1.0, b: nil}) == "1-null"
      assert js("`a${x}b`", %{x: 1}) == "a1b"
    end
  end
end
