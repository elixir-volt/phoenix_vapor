defmodule PhoenixVapor.Hybrid.ClientCodegenTest do
  use ExUnit.Case, async: true

  alias PhoenixVapor.Hybrid.{Classifier, ClientCodegen}

  defp classify(script) do
    script |> PhoenixVapor.Compiler.ScriptSetup.parse() |> Classifier.classify()
  end

  defp generate(sfc_source) do
    script =
      case Vize.parse_sfc!(sfc_source) do
        %{script_setup: %{content: c}} -> c
        _ -> ""
      end

    classification = classify(script)
    {:ok, js} = ClientCodegen.generate(sfc_source, classification)
    js
  end

  describe "generate/2" do
    test "registers the refs for a recorded session before setup returns" do
      js =
        generate("""
        <script setup>
        import { ref } from "vue"
        const search = ref("")
        const page = ref(1)
        </script>
        <template><p>{{ search }} {{ page }}</p></template>
        """)

      # Vize's setup ends with its render function's return; registering
      # depends on it.
      assert js =~ ~r/__pv\?\.record\(\{ (search, page|page, search) \}\);\s*return/
      assert js =~ "bridge.record?.(sources, __watch, __unref)"
      assert {:ok, _} = OXC.parse(js, "output.js")
    end

    test "produces valid JavaScript" do
      js =
        generate("""
        <script setup>
        import { ref } from "vue"
        defineProps(["count"])
        const search = ref("")
        </script>
        <template><p>{{ count }}</p></template>
        """)

      assert {:ok, _} = OXC.parse(js, "output.js")
    end

    test "includes the client state list and the instance context" do
      js =
        generate("""
        <script setup>
        import { ref } from "vue"
        defineProps(["users"])
        const search = ref("")
        </script>
        <template><p>{{ search }}</p></template>
        """)

      assert js =~ ~s|export function __getClientState() {\n  return ["search"];|
      assert js =~ ~s|const __pv = __inject("__pv");|
    end

    test "includes mount export" do
      js =
        generate("""
        <script setup>
        defineProps(["x"])
        </script>
        <template><p>{{ x }}</p></template>
        """)

      assert js =~ "__mount"
      assert js =~ "__component"
    end

    test "keeps the props binding pointing at __props" do
      js =
        generate("""
        <script setup>
        import { ref, computed } from "vue"
        const props = defineProps(["users"])
        const search = ref("")
        const filtered = computed(() => props.users.filter(u => u.name.includes(search.value)))
        </script>
        <template><p>{{ filtered.length }}</p></template>
        """)

      assert js =~ "const props = __props"
    end

    test "preserves Vue Vapor render function" do
      js =
        generate("""
        <script setup>
        import { ref } from "vue"
        defineProps(["title"])
        const search = ref("")
        </script>
        <template>
          <h1>{{ title }}</h1>
          <input :value="search" />
        </template>
        """)

      assert js =~ "createElementBlock" or js =~ "createElementVNode"
      assert js =~ "createElementBlock" or js =~ "openBlock"
      assert js =~ "toDisplayString"
      assert js =~ "createElementVNode" or js =~ "openBlock"
    end

    test "lists client state keys" do
      js =
        generate("""
        <script setup>
        import { ref } from "vue"
        defineProps(["data"])
        const search = ref("")
        const page = ref(1)
        </script>
        <template><p>{{ search }}</p></template>
        """)

      assert js =~ ~s("search")
      assert js =~ ~s("page")
      assert js =~ "__getClientState"
    end
  end

  describe "server action rewriting" do
    test "a server action sends itself through the bridge" do
      js =
        generate("""
        <script setup>
        import { ref } from "vue"
        defineProps(["users"])
        const search = ref("")
        function deleteUser(id) { "use server"; users = users.filter(u => u.id !== id) }
        </script>
        <template><button @click="deleteUser(1)">x</button></template>
        """)

      assert js =~ "__pv.bridge.action"
      assert js =~ ~s("deleteUser")
    end

    test "runs the action's body, then sends the action, unless the body returns first" do
      js =
        generate("""
        <script setup>
        const users = defineModel("users")
        function deleteUser(id) {
          "use server"
          if (!id) return
          users.value = users.value.filter(u => u.id !== id)
        }
        </script>
        <template><button @click="deleteUser(1)">x</button></template>
        """)

      assert js =~
               ~s|if (!id) return\n  users.value = users.value.filter(u => u.id !== id)\n\n  __pv.bridge.action("deleteUser", {"id": id});|

      refute js =~ ~s|"use server"|
      assert {:ok, _ast} = OXC.parse(js, "client.js")
    end

    test "the mount applies each model's update to its props" do
      js =
        generate("""
        <script setup>
        const users = defineModel("users")
        const open = defineModel("open")
        </script>
        <template><p>{{ users.length }} {{ open }}</p></template>
        """)

      assert js =~ ~s|const __models = ["open","users"];|
      assert js =~ ~s|__h(__component, { ...state, ...listeners })|
    end

    test "client handler is NOT rewritten" do
      js =
        generate("""
        <script setup>
        import { ref } from "vue"
        defineProps(["users"])
        const search = ref("")
        function clearSearch() { search.value = "" }
        </script>
        <template><button @click="clearSearch">x</button></template>
        """)

      # clearSearch body should remain as-is
      assert js =~ ~s(search.value = "")
    end
  end

  describe "transform/2" do
    test "output is parseable JS" do
      sfc = """
      <script setup>
      import { ref, computed } from "vue"
      defineProps(["users", "currentUser"])
      const search = ref("")
      const filtered = computed(() => users.filter(u => u.name.includes(search.value)))
      function clearSearch() { search.value = "" }
      function deleteUser(id) { "use server"; users = users.filter(u => u.id !== id) }
      </script>
      <template>
        <div>
          <input :value="search" @input="search = $event.target.value" />
          <p>{{ filtered.length }} results</p>
          <button @click="clearSearch">Clear</button>
          <button @click="deleteUser(1)">Delete</button>
        </div>
      </template>
      """

      script =
        case Vize.parse_sfc!(sfc) do
          %{script_setup: %{content: c}} -> c
        end

      classification = classify(script)
      {:ok, result} = Vize.compile_sfc(sfc, vapor: true)
      js = ClientCodegen.transform(result.code, classification)

      # Must be valid JavaScript
      case OXC.parse(js, "output.js") do
        {:ok, _} -> :ok
        {:error, errors} -> flunk("Generated JS is not valid:\n#{inspect(errors)}\n\n#{js}")
      end
    end
  end
end
