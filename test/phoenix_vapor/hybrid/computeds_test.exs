defmodule PhoenixVapor.Hybrid.ComputedsTest do
  use ExUnit.Case, async: true

  alias PhoenixVapor.Compiler.ScriptSetup
  alias PhoenixVapor.Hybrid.Computeds

  @setup ScriptSetup.parse("""
         import { ref, computed } from "vue"
         const props = defineProps(["contacts"])
         const search = ref("")
         const selected = ref([1, 2])
         const visible = computed(() => {
           const term = search.value.toLowerCase()
           return props.contacts.filter(c => c.name.toLowerCase().includes(term))
         })
         const count = computed(() => selected.value.length)
         const summary = computed(() => `${count.value} of ${visible.value.length}`)
         """)

  test "orders computeds after what they read, and splits off those that read props" do
    {constant, per_render} = Computeds.compile(@setup)

    assert Enum.map(constant, &elem(&1, 0)) == ["count"]
    assert Enum.map(per_render, &elem(&1, 0)) == ["visible", "summary"]
  end

  test "evaluates computeds with refs read as .value" do
    {constant, per_render} = Computeds.compile(@setup)
    refs = %{search: "a", selected: [1, 2]}

    {values, _assigns} = Computeds.evaluate(constant, refs, refs)
    assert values.count == 2

    # Rendering puts the props under `props` too, as `defineProps` returns them.
    contacts = [%{"name" => "Ada"}, %{"name" => "Bob"}]
    assigns = Map.merge(values, %{contacts: contacts, props: %{"contacts" => contacts}})
    {_values, assigns} = Computeds.evaluate(per_render, values, assigns, memo: true)

    assert assigns.visible == [%{"name" => "Ada"}]
    assert assigns.summary == "2 of 1"
  end

  test "a computed that fails raises, rather than rendering as missing" do
    {_constant, per_render} = Computeds.compile(@setup)

    assert_raise PhoenixVapor.ExpressionError, fn ->
      assigns = %{contacts: nil, props: %{"contacts" => nil}}
      Computeds.evaluate(per_render, %{search: "", selected: []}, assigns, memo: true)
    end
  end
end
