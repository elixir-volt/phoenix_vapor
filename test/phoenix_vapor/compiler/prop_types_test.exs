defmodule PhoenixVapor.Compiler.PropTypesTest do
  use ExUnit.Case, async: true

  alias PhoenixVapor.Compiler.PropTypes

  @moduletag :tmp_dir

  # The SFC lives in the project, so TypeScript resolves from its node_modules.
  setup %{tmp_dir: tmp_dir} do
    dir = Path.join(File.cwd!(), "tmp/prop_types/#{Path.basename(tmp_dir)}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  test "types template expressions, refs unwrapped, props declared" do
    script = """
    import { ref, computed } from "vue"
    defineProps<{ size: "sm" | "md" }>()
    const tab = ref<"a" | "b">("a")
    const on = ref(false)
    const query = ref("")
    const open = computed(() => on.value && tab.value === "a")
    """

    assert {:ok, types} =
             PropTypes.expression_values(Path.join(File.cwd!(), "test/fixtures/X.vue"), script, [
               "tab",
               "on",
               "query",
               "open",
               "size"
             ])

    assert Enum.map(types, & &1["values"]) == [
             ["a", "b"],
             [false, true],
             nil,
             [false, true],
             ["sm", "md"]
           ]
  end

  test "reads a type file again once it changes", %{dir: dir} do
    types = Path.join(dir, "types.ts")
    file = Path.join(dir, "Tabs.vue")

    script = """
    import { ref } from "vue"
    import type { Tab } from "./types"
    const tab = ref<Tab>("a")
    """

    File.write!(types, ~s(export type Tab = "a" | "b"\n))
    assert {:ok, [%{"values" => ["a", "b"]}]} = PropTypes.expression_values(file, script, ["tab"])

    File.write!(types, ~s(export type Tab = "a" | "b" | "c"\n))
    File.touch!(types, System.os_time(:second) + 5)

    assert {:ok, [%{"values" => ["a", "b", "c"]}]} =
             PropTypes.expression_values(file, script, ["tab"])
  end
end
