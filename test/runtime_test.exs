defmodule PhoenixVapor.RuntimeTest do
  use ExUnit.Case, async: false
  alias PhoenixVapor.Runtime

  describe "basic ref state" do
    test "initial state from refs" do
      {:ok, rt} = Runtime.start_link(refs: %{"count" => "0", "name" => ~s("World")})
      {:ok, state} = Runtime.get_state(rt)
      assert state["count"] == 0
      assert state["name"] == "World"
      GenServer.stop(rt)
    end

    test "set_state updates refs" do
      {:ok, rt} = Runtime.start_link(refs: %{"x" => "1", "y" => "2"})
      {:ok, state} = Runtime.set_state(rt, %{"x" => 10})
      assert state["x"] == 10
      assert state["y"] == 2
      GenServer.stop(rt)
    end
  end

  describe "computed values" do
    test "computed auto-updates when ref changes" do
      {:ok, rt} =
        Runtime.start_link(
          refs: %{"count" => "0"},
          computeds: %{"doubled" => "count * 2", "label" => ~s{count > 0 ? "pos" : "non-pos"}}
        )

      {:ok, s} = Runtime.get_state(rt)
      assert s["doubled"] == 0
      assert s["label"] == "non-pos"

      {:ok, s} = Runtime.set_state(rt, %{"count" => 5})
      assert s["doubled"] == 10
      assert s["label"] == "pos"

      GenServer.stop(rt)
    end

    test "computed depending on multiple refs" do
      {:ok, rt} =
        Runtime.start_link(
          refs: %{"a" => "1", "b" => "2"},
          computeds: %{"sum" => "a + b", "product" => "a * b"}
        )

      {:ok, s} = Runtime.get_state(rt)
      assert s["sum"] == 3
      assert s["product"] == 2

      {:ok, s} = Runtime.set_state(rt, %{"a" => 10, "b" => 3})
      assert s["sum"] == 13
      assert s["product"] == 30

      GenServer.stop(rt)
    end
  end

  describe "event handlers" do
    test "function mutates ref via with(scope)" do
      {:ok, rt} =
        Runtime.start_link(
          refs: %{"count" => "0"},
          computeds: %{"doubled" => "count * 2"},
          functions: ["increment", "decrement", "reset"],
          function_bodies: %{
            "increment" => "count++",
            "decrement" => "count--",
            "reset" => "count = 0"
          }
        )

      {:ok, s} = Runtime.call_handler(rt, "increment")
      assert s["count"] == 1
      assert s["doubled"] == 2

      {:ok, s} = Runtime.call_handler(rt, "increment")
      {:ok, s} = Runtime.call_handler(rt, "increment")
      assert s["count"] == 3
      assert s["doubled"] == 6

      {:ok, s} = Runtime.call_handler(rt, "decrement")
      assert s["count"] == 2

      {:ok, s} = Runtime.call_handler(rt, "reset")
      assert s["count"] == 0
      assert s["doubled"] == 0

      GenServer.stop(rt)
    end

    test "function with array mutation" do
      {:ok, rt} =
        Runtime.start_link(
          refs: %{"items" => ~s{["a", "b"]}},
          computeds: %{"count" => "items.length"},
          functions: ["addItem", "removeFirst"],
          function_bodies: %{
            "addItem" => "items.push(\"item\" + (items.length + 1))",
            "removeFirst" => "items.shift()"
          }
        )

      {:ok, s} = Runtime.get_state(rt)
      assert s["items"] == ["a", "b"]
      assert s["count"] == 2

      {:ok, s} = Runtime.call_handler(rt, "addItem")
      assert s["items"] == ["a", "b", "item3"]
      assert s["count"] == 3

      {:ok, s} = Runtime.call_handler(rt, "removeFirst")
      assert s["items"] == ["b", "item3"]
      assert s["count"] == 2

      GenServer.stop(rt)
    end

    test "function with object mutation" do
      {:ok, rt} =
        Runtime.start_link(
          refs: %{"user" => ~s|{name: "Alice", age: 30}|},
          computeds: %{"greeting" => ~s{"Hi " + user.name}},
          functions: ["rename"],
          function_bodies: %{"rename" => ~s{user.name = __params.name}}
        )

      {:ok, s} = Runtime.get_state(rt)
      assert s["greeting"] == "Hi Alice"

      {:ok, s} = Runtime.call_handler(rt, "rename", %{"name" => "Bob"})
      assert s["greeting"] == "Hi Bob"

      GenServer.stop(rt)
    end

    test "handler receives params" do
      {:ok, rt} =
        Runtime.start_link(
          refs: %{"value" => "0"},
          functions: ["setValue"],
          function_bodies: %{"setValue" => "value = Number(__params.value)"}
        )

      {:ok, s} = Runtime.call_handler(rt, "setValue", %{"value" => "42"})
      assert s["value"] == 42

      GenServer.stop(rt)
    end
  end

  describe "state persistence" do
    test "state persists across multiple handler calls" do
      {:ok, rt} =
        Runtime.start_link(
          refs: %{"history" => "[]"},
          functions: ["record"],
          function_bodies: %{"record" => ~s{history.push(__params.event)}}
        )

      {:ok, _} = Runtime.call_handler(rt, "record", %{"event" => "click"})
      {:ok, _} = Runtime.call_handler(rt, "record", %{"event" => "hover"})
      {:ok, s} = Runtime.call_handler(rt, "record", %{"event" => "submit"})
      assert s["history"] == ["click", "hover", "submit"]

      GenServer.stop(rt)
    end
  end

  describe "complex reactive chains" do
    test "computed chain: a → b → c" do
      {:ok, rt} =
        Runtime.start_link(
          refs: %{"base" => "1"},
          computeds: %{
            "doubled" => "base * 2",
            "quadrupled" => "doubled * 2"
          }
        )

      {:ok, s} = Runtime.get_state(rt)
      assert s["base"] == 1
      assert s["doubled"] == 2
      assert s["quadrupled"] == 4

      {:ok, s} = Runtime.set_state(rt, %{"base" => 5})
      assert s["doubled"] == 10
      assert s["quadrupled"] == 20

      GenServer.stop(rt)
    end

    test "multiple refs in one computed" do
      {:ok, rt} =
        Runtime.start_link(
          refs: %{"first" => ~s{"Alice"}, "last" => ~s{"Smith"}},
          computeds: %{"full" => ~s{first + " " + last}}
        )

      {:ok, s} = Runtime.get_state(rt)
      assert s["full"] == "Alice Smith"

      {:ok, s} = Runtime.set_state(rt, %{"first" => "Bob"})
      assert s["full"] == "Bob Smith"

      GenServer.stop(rt)
    end

    test "handler modifying multiple refs" do
      {:ok, rt} =
        Runtime.start_link(
          refs: %{"x" => "0", "y" => "0"},
          computeds: %{"sum" => "x + y"},
          functions: ["moveTo"],
          function_bodies: %{"moveTo" => "x = Number(__params.x); y = Number(__params.y)"}
        )

      {:ok, s} = Runtime.call_handler(rt, "moveTo", %{"x" => "3", "y" => "4"})
      assert s["x"] == 3
      assert s["y"] == 4
      assert s["sum"] == 7

      GenServer.stop(rt)
    end

    test "conditional computed" do
      {:ok, rt} =
        Runtime.start_link(
          refs: %{"value" => "0"},
          computeds: %{"status" => ~s{value > 0 ? "positive" : value < 0 ? "negative" : "zero"}}
        )

      {:ok, s} = Runtime.get_state(rt)
      assert s["status"] == "zero"

      {:ok, s} = Runtime.set_state(rt, %{"value" => 5})
      assert s["status"] == "positive"

      {:ok, s} = Runtime.set_state(rt, %{"value" => -1})
      assert s["status"] == "negative"

      GenServer.stop(rt)
    end
  end
end
