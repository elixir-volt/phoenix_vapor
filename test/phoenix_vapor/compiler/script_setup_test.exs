defmodule PhoenixVapor.ScriptSetupTest do
  use ExUnit.Case, async: true

  alias PhoenixVapor.Compiler.ScriptSetup

  describe "parse/1" do
    test "extracts refs with initial values" do
      %ScriptSetup{refs: refs} =
        ScriptSetup.parse("""
        import { ref } from "vue"
        const count = ref(0)
        const name = ref("hello")
        """)

      assert refs == %{"count" => "0", "name" => "\"hello\""}
    end

    test "extracts computed expressions" do
      %ScriptSetup{computeds: computeds} =
        ScriptSetup.parse("""
        import { ref, computed } from "vue"
        const count = ref(0)
        const doubled = computed(() => count.value * 2)
        """)

      assert computeds["doubled"] == "count.value * 2"
    end

    test "extracts function names" do
      %ScriptSetup{functions: functions} =
        ScriptSetup.parse("""
        function increment() { count.value++ }
        function reset() { count.value = 0 }
        """)

      assert functions == %{"increment" => "count.value++", "reset" => "count.value = 0"}
    end

    test "extracts defineProps" do
      %ScriptSetup{props: props} = ScriptSetup.parse(~s|defineProps(["title", "count"])|)

      assert props == ["title", "count"]
    end
  end

  describe "eval_initial_state/2" do
    test "evaluates initial state via QuickBEAM" do
      refs = %{"count" => "0", "items" => "[]", "name" => "\"world\""}
      state = ScriptSetup.eval_initial_state(refs, start_supervised!(QuickBEAM))

      assert state.count == 0
      assert state.items == []
      assert state.name == "world"
    end
  end

  describe "parse/1 for the compiler" do
    test "reads imports with their attributes, top-level constants and callables" do
      setup =
        ScriptSetup.parse("""
        import Card from "./Card.vue"
        import { button } from "./variants" with { type: "macro" }
        const classes = button({ size: "sm" })
        const format = (n) => n.toFixed(2)
        function roleTone(role) { return role }
        """)

      assert setup.imports["Card"] == %{source: "./Card.vue", imported: :default, attributes: %{}}
      assert setup.imports["button"].attributes == %{"type" => "macro"}
      assert [{"classes", _node, ~s|button({ size: "sm" })|}, {"format", _, _}] = setup.consts
      assert setup.callables == ["format", "roleTone"]
    end

    test "a script that doesn't parse declares nothing" do
      assert %ScriptSetup{refs: %{}, functions: %{}, props: []} = ScriptSetup.parse("const = ")
    end
  end

  describe "client bindings" do
    test "are names bound by calls the compiler can't run, destructured too" do
      setup =
        ScriptSetup.parse("""
        import { ref, computed, reactive } from "vue"
        import { refDebounced, useClipboard } from "@vueuse/core"
        import { badge } from "./variants" with { type: "macro" }
        const props = defineProps(["a"])
        const search = ref("")
        const debounced = refDebounced(search, 150)
        const { copy, copied } = useClipboard()
        const state = reactive({ open: false })
        const classes = badge({ tone: "a" })
        const doubled = computed(() => 2)
        const roles = ["a"]
        """)

      assert setup.client_bindings == ["debounced", "copy", "copied", "state"]
    end

    test "make a file hybrid even without a ref()" do
      sfc = %PhoenixVapor.Compiler.SFC{
        file: "x.vue",
        source: "",
        setup: ScriptSetup.parse(~s|const { copied } = useClipboard()|)
      }

      assert PhoenixVapor.Compiler.SFC.client_state?(sfc)

      refute PhoenixVapor.Compiler.SFC.client_state?(%{
               sfc
               | setup: ScriptSetup.parse("const a = 1")
             })
    end
  end
end
