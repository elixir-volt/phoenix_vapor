defmodule PhoenixVapor.Hybrid.ClientCodegenTest do
  use ExUnit.Case, async: true

  alias PhoenixVapor.Hybrid.{Classifier, ClientCodegen}

  defp classify(script) do
    {refs, computeds, functions, function_bodies, props} =
      PhoenixVapor.ScriptSetup.parse(script)

    Classifier.classify(refs, computeds, functions, function_bodies, props)
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

    test "includes bridge preamble" do
      js =
        generate("""
        <script setup>
        import { ref } from "vue"
        defineProps(["users"])
        const search = ref("")
        </script>
        <template><p>{{ search }}</p></template>
        """)

      assert js =~ "__propsState"
      assert js =~ "__propsState"
      assert js =~ "__applyProps"
      assert js =~ "__setBridge"
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

    test "replaces __props with __propsState" do
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

      assert js =~ "__propsState"
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
    test "rewrites server action to pushEvent call" do
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

      assert js =~ "pushEvent"
      assert js =~ ~s("deleteUser")
    end

    test "generates optimistic update for prop assignment" do
      js =
        generate("""
        <script setup>
        defineProps(["users"])
        function deleteUser(id) { "use server"; users = users.filter(u => u.id !== id) }
        </script>
        <template><button @click="deleteUser(1)">x</button></template>
        """)

      assert js =~ "__propsState"
      assert js =~ "triggerRef"
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
