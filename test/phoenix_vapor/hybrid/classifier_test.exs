defmodule PhoenixVapor.Hybrid.ClassifierTest do
  use ExUnit.Case, async: true

  alias PhoenixVapor.Hybrid.Classifier

  describe "free_variables/1" do
    test "simple identifier" do
      assert Classifier.free_variables("x") == ["x"]
    end

    test "binary expression" do
      assert Classifier.free_variables("a + b") == ["a", "b"]
    end

    test "member expression — only object is free" do
      assert Classifier.free_variables("items.length") == ["items"]
    end

    test "deep member chain" do
      assert Classifier.free_variables("user.address.city") == ["user"]
    end

    test "computed member — index is free" do
      assert Classifier.free_variables("items[idx]") == ["idx", "items"]
    end

    test "arrow function params are bound" do
      assert Classifier.free_variables("arr.filter(x => x > 0)") == ["arr"]
    end

    test "arrow function with free var in body" do
      assert Classifier.free_variables("arr.map(item => item.name + suffix)") == ["arr", "suffix"]
    end

    test "nested arrow functions" do
      assert Classifier.free_variables("a.map(x => b.filter(y => x + y + z))") == ["a", "b", "z"]
    end

    test "ternary expression" do
      assert Classifier.free_variables("x > 0 ? x : y") == ["x", "y"]
    end

    test "unary expression" do
      assert Classifier.free_variables("!hidden") == ["hidden"]
    end

    test "template literal" do
      assert Classifier.free_variables("`hello ${name}`") == ["name"]
    end

    test "logical expression" do
      assert Classifier.free_variables("a && b || c") == ["a", "b", "c"]
    end

    test "assignment target is free" do
      assert Classifier.free_variables("x = y + 1") == ["x", "y"]
    end

    test "call expression with multiple args" do
      assert Classifier.free_variables("fn(a, b, c)") == ["a", "b", "c", "fn"]
    end

    test "method call — only object and args are free" do
      assert Classifier.free_variables("users.filter(u => u.name.includes(search.value))") == ["search", "users"]
    end

    test "object literal" do
      assert Classifier.free_variables("({ key: value, other: x })") == ["value", "x"]
    end

    test "array literal" do
      assert Classifier.free_variables("[a, b, c]") == ["a", "b", "c"]
    end

    test "string literal has no free vars" do
      assert Classifier.free_variables("\"hello\"") == []
    end

    test "numeric literal has no free vars" do
      assert Classifier.free_variables("42") == []
    end

    test "boolean literal has no free vars" do
      assert Classifier.free_variables("true") == []
    end

    test "destructuring params are bound" do
      assert Classifier.free_variables("arr.map(({name, id}) => name + id + extra)") == ["arr", "extra"]
    end

    test "variable declaration binds name" do
      assert Classifier.free_variables("const x = y + z") == ["y", "z"]
    end
  end

  describe "classify/5" do
    test "basic classification" do
      result =
        Classifier.classify(
          %{"search" => ~s(""), "page" => "1"},
          %{"filtered" => "users.filter(u => u.name.includes(search.value))"},
          ["clearSearch", "deleteUser"],
          %{
            "clearSearch" => ~s[search.value = ""; page.value = 1],
            "deleteUser" => ~s["use server"; users = users.filter(u => u.id !== id)]
          },
          ["users", "currentUser"]
        )

      assert result.bindings["users"] == :server_prop
      assert result.bindings["currentUser"] == :server_prop
      assert result.bindings["search"] == {:client_ref, ~s("")}
      assert result.bindings["page"] == {:client_ref, "1"}

      assert {:mixed_computed, ["users"], ["search"]} = result.bindings["filtered"]
    end

    test "classifies server action via use server directive" do
      result =
        Classifier.classify(
          %{},
          %{},
          ["deleteUser"],
          %{"deleteUser" => ~s["use server"; users = users.filter(u => u.id !== id)]},
          ["users"]
        )

      assert {:server_action, body} = result.handlers["deleteUser"]
      assert body =~ "users = users.filter"
      refute body =~ "use server"
    end

    test "classifies server action via prop write (no directive)" do
      result =
        Classifier.classify(
          %{},
          %{},
          ["banUser"],
          %{"banUser" => "users = users.map(u => u.id === id ? {...u, banned: true} : u)"},
          ["users"]
        )

      assert {:server_action, _body} = result.handlers["banUser"]
    end

    test "classifies client handler" do
      result =
        Classifier.classify(
          %{"search" => ~s(""), "page" => "1"},
          %{},
          ["clearSearch"],
          %{"clearSearch" => ~s[search.value = ""; page.value = 1]},
          ["users"]
        )

      assert result.handlers["clearSearch"] == :client_handler
    end

    test "identifies client props" do
      result =
        Classifier.classify(
          %{"search" => ~s("")},
          %{"filtered" => "users.filter(u => u.name.includes(search.value))"},
          [],
          %{},
          ["users", "currentUser"]
        )

      assert "users" in result.client_props
      refute "currentUser" in result.client_props
      assert "currentUser" in result.server_only_props
    end

    test "pure client computed (no server deps)" do
      result =
        Classifier.classify(
          %{"search" => ~s(""), "items" => "[]"},
          %{"upper" => "search.value.toUpperCase()"},
          [],
          %{},
          ["users"]
        )

      assert result.bindings["upper"] == :client_computed
    end

    test "multiple server deps in computed" do
      result =
        Classifier.classify(
          %{"filter" => ~s("")},
          %{"combined" => "users.concat(admins).filter(u => u.name.includes(filter.value))"},
          [],
          %{},
          ["users", "admins", "currentUser"]
        )

      assert {:mixed_computed, server_deps, ["filter"]} = result.bindings["combined"]
      assert "users" in server_deps
      assert "admins" in server_deps
      assert "users" in result.client_props
      assert "admins" in result.client_props
      refute "currentUser" in result.client_props
    end

    test "function calling update expression on prop" do
      result =
        Classifier.classify(
          %{},
          %{},
          ["increment"],
          %{"increment" => "count++"},
          ["count"]
        )

      assert {:server_action, "count++"} = result.handlers["increment"]
    end

    test "empty script setup" do
      result = Classifier.classify(%{}, %{}, [], %{}, [])
      assert result.bindings == %{}
      assert result.handlers == %{}
      assert result.client_props == []
      assert result.server_only_props == []
    end
  end
end
