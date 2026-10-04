defmodule PhoenixVapor.ExprTest do
  use ExUnit.Case, async: true

  alias PhoenixVapor.Renderer.Expr

  # Templates compile each expression once, then evaluate it per render.
  defp eval(source, assigns), do: source |> Expr.compile() |> Expr.eval(assigns)
  defp keys(source), do: source |> Expr.compile() |> Expr.assign_keys()

  describe "eval/2" do
    test "resolves identifiers and nested access" do
      assert eval("msg", %{msg: "hello"}) == "hello"
      assert eval("user.name", %{user: %{name: "Dan"}}) == "Dan"

      assigns = %{user: %{address: %{city: "Moscow"}}}
      assert eval("user.address.city", assigns) == "Moscow"
    end

    test "supports atom and string keys" do
      assert eval("x", %{x: 1}) == 1
      assert eval("x", %{"x" => 2}) == 2
    end

    test "returns nil for missing keys" do
      assert eval("missing", %{}) == nil
    end

    test "evaluates literals" do
      assert eval("true", %{}) == true
      assert eval("false", %{}) == false
      assert eval("null", %{}) == nil
    end

    test "evaluates conditional expressions" do
      assert eval(~s[ok ? "y" : "n"], %{ok: true}) == "y"
      assert eval(~s[ok ? "y" : "n"], %{ok: false}) == "n"
    end

    test "evaluates arithmetic and comparisons" do
      assert eval("a + b", %{a: 2, b: 3}) == 5
      assert eval("a - b", %{a: 10, b: 3}) == 7
      assert eval("a * b", %{a: 4, b: 5}) == 20
      assert eval("a > b", %{a: 5, b: 3}) == true
      assert eval("a === b", %{a: 1, b: 1}) == true
      assert eval("a !== b", %{a: 1, b: 2}) == true
    end

    test "evaluates logical expressions" do
      assert eval("a && b", %{a: true, b: "yes"}) == "yes"
      assert eval("a && b", %{a: false, b: "yes"}) == false
      assert eval("a || b", %{a: nil, b: "fallback"}) == "fallback"
      assert eval("a ?? b", %{a: nil, b: "default"}) == "default"
      assert eval("a ?? b", %{a: 0, b: "default"}) == 0
    end

    test "evaluates unary expressions" do
      assert eval("!x", %{x: false}) == true
      assert eval("-x", %{x: 5}) == -5
    end

    test "evaluates member and array access" do
      assert eval("items.length", %{items: [1, 2, 3]}) == 3
      assert eval("items[1]", %{items: ["a", "b", "c"]}) == "b"
    end

    test "evaluates typeof" do
      assert eval("typeof x", %{x: 42}) == "number"
      assert eval("typeof x", %{x: "hi"}) == "string"
      # `nil` is `null`, whose type is "object"; a missing name is `undefined`.
      assert eval("typeof x", %{x: nil}) == "object"
      assert eval("typeof x", %{}) == "undefined"
    end

    test "evaluates string and array methods" do
      assert eval(~s[s.trim()], %{s: "  hi  "}) == "hi"
      assert eval(~s[s.toUpperCase()], %{s: "hi"}) == "HI"
      assert eval(~s[s.toLowerCase()], %{s: "HI"}) == "hi"

      assigns = %{items: ["a", "b", "c"]}
      assert eval(~s[items.includes("b")], assigns) == true
      assert eval(~s[items.includes("z")], assigns) == false
    end
  end

  describe "assign_keys/1" do
    test "extracts identifiers" do
      assert keys("msg") == ["msg"]
      assert "user" in keys("user.name")
      assert Expr.assign_keys({:value, "text"}) == []
    end

    test "extracts identifiers from complex expressions" do
      keys = keys("a > b ? x : y")
      assert "a" in keys
      assert "b" in keys
      assert "x" in keys
      assert "y" in keys
    end
  end

  describe "JavaScript semantics" do
    test "truthiness follows JavaScript" do
      assert eval(~s(count ? "yes" : "no"), %{count: 0}) == "no"
      assert eval(~s(count ? "yes" : "no"), %{count: 0.0}) == "no"
      assert eval("!name", %{name: ""}) == true
      assert eval(~s(label || "fallback"), %{label: ""}) == "fallback"
      assert eval(~s(items && items.length), %{items: []}) == 0
      assert eval(~s(x ?? "default"), %{}) == "default"
      assert eval(~s(x ?? "default"), %{x: 0}) == 0
    end

    test "comparisons convert as JavaScript does" do
      # `undefined > 0` is false, though Elixir orders atoms after numbers.
      assert eval("items.length > 0", %{}) == false
      assert eval("count > 0", %{count: nil}) == false
      assert eval("count === 1", %{count: 1.0}) == true
      assert eval(~s(count == "1"), %{count: 1}) == true
      assert eval(~s(count === "1"), %{count: 1}) == false
      assert eval("x == null", %{}) == true
      assert eval(~s("b" > "a"), %{}) == true
      assert eval(~s("10" < 9), %{}) == false
    end

    test "arithmetic and concatenation convert as JavaScript does" do
      assert eval("a + b", %{a: "1", b: 2}) == "12"
      assert eval("a + b", %{a: 1, b: 2}) == 3
      assert eval("n + 1", %{n: nil}) == 1
      assert eval("n + 1", %{}) == :nan
      assert eval("1 / 0", %{}) == :infinity
      assert eval(~s("x" * 2), %{}) == :nan
      assert eval("`${a}-${b}`", %{a: 1.0, b: nil}) == "1-null"
      assert eval("`a${x}b`", %{x: 1}) == "a1b"
    end
  end
end
