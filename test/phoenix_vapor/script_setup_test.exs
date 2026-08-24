defmodule PhoenixVapor.ScriptSetupTest do
  use ExUnit.Case, async: true

  alias PhoenixVapor.ScriptSetup

  describe "parse/1" do
    test "extracts refs with initial values" do
      {refs, _, _, _, _} =
        ScriptSetup.parse("""
        import { ref } from "vue"
        const count = ref(0)
        const name = ref("hello")
        """)

      assert refs == %{"count" => "0", "name" => "\"hello\""}
    end

    test "extracts computed expressions" do
      {_, computeds, _, _, _} =
        ScriptSetup.parse("""
        import { ref, computed } from "vue"
        const count = ref(0)
        const doubled = computed(() => count.value * 2)
        """)

      assert computeds["doubled"] == "count.value * 2"
    end

    test "extracts function names" do
      {_, _, functions, _, _} =
        ScriptSetup.parse("""
        function increment() { count.value++ }
        function reset() { count.value = 0 }
        """)

      assert "increment" in functions
      assert "reset" in functions
    end

    test "extracts defineProps" do
      {_, _, _, _, props} = ScriptSetup.parse(~s|defineProps(["title", "count"])|)

      assert props == ["title", "count"]
    end
  end

  describe "eval_initial_state/1" do
    test "evaluates initial state via QuickBEAM" do
      refs = %{"count" => "0", "items" => "[]", "name" => "\"world\""}
      state = ScriptSetup.eval_initial_state(refs)

      assert state.count == 0
      assert state.items == []
      assert state.name == "world"
    end
  end
end
