defmodule PhoenixVapor.E2E.HybridClientTest do
  use ExUnit.Case, async: true

  alias PhoenixVapor.Hybrid.{Classifier, ClientCodegen}

  @moduletag :e2e
  @moduletag :tmp_dir

  @node_modules Path.join(File.cwd!(), "node_modules")

  unless File.dir?(Path.join(@node_modules, "vue")) do
    @moduletag skip: "node_modules/vue not found; install it with `mix npm.install`"
  end

  @sfc """
  <script setup>
  import { ref } from "vue"

  const users = defineModel("users")
  const note = ref("bye")
  const selected = ref([2])

  function remove(id) {
    "use server"
    // Already removed: nothing to send.
    if (!users.value.some(u => u.id === id)) return
    users.value = users.value.filter(u => u.id !== id)
  }

  function removeSelected() {
    "use server"
    users.value = users.value.filter(u => !selected.value.includes(u.id))
    selected.value = []
  }
  </script>

  <template>
    <ul>
      <li v-for="u in users" :key="u.id">{{ u.name }}</li>
    </ul>
    <button @click="remove(1)">Remove</button>
    <button class="selected" @click="removeSelected()">Remove selected</button>
  </template>
  """

  setup %{tmp_dir: tmp_dir} do
    rt = start_supervised!(QuickBEAM)

    %{script_setup: %{content: script}} = Vize.parse_sfc!(@sfc)
    classification = script |> PhoenixVapor.Compiler.ScriptSetup.parse() |> Classifier.classify()

    {:ok, js} = ClientCodegen.generate(@sfc, classification)

    File.write!(Path.join(tmp_dir, "component.js"), js)

    File.write!(Path.join(tmp_dir, "entry.js"), """
    import { __mount } from "./component.js";

    // Two instances of the same component, each with its own props and bridge.
    globalThis.events = { a: [], b: [] };
    globalThis.instances = {};

    for (const [id, users] of [
      ["a", [{ id: 1, name: "Ann" }, { id: 2, name: "Bob" }]],
      ["b", [{ id: 1, name: "Cat" }, { id: 2, name: "Dan" }]]
    ]) {
      const el = document.createElement("div");
      el.id = id;
      document.body.appendChild(el);
      instances[id] = __mount(el, { action: (event, params) => events[id].push([event, params]) }, { users });
    }
    """)

    {:ok, _} =
      Volt.Builder.build(
        entry: Path.join(tmp_dir, "entry.js"),
        outdir: tmp_dir,
        node_modules: @node_modules,
        name: "bundle",
        hash: false,
        sourcemap: false,
        write_manifest: false,
        define: %{"process.env.NODE_ENV" => ~s("production")}
      )

    {:ok, _} = QuickBEAM.eval(rt, File.read!(Path.join(tmp_dir, "bundle.js")))
    %{rt: rt}
  end

  defp html(rt, id) do
    {:ok, html} = QuickBEAM.eval(rt, ~s|document.getElementById("#{id}").innerHTML|)
    html
  end

  test "mounts each instance with its own props", %{rt: rt} do
    assert html(rt, "a") =~ "Ann"
    assert html(rt, "b") =~ "Cat"
    refute html(rt, "a") =~ "Cat"
  end

  test "a server action updates its own instance and pushes through its own bridge", %{rt: rt} do
    {:ok, _} =
      QuickBEAM.eval(
        rt,
        ~s|document.querySelector("#a button").dispatchEvent(new Event("click"))|
      )

    refute html(rt, "a") =~ "Ann"
    assert html(rt, "a") =~ "Bob"
    assert html(rt, "b") =~ "Cat"

    assert {:ok, %{"a" => [["remove", %{"id" => 1}]], "b" => []}} =
             QuickBEAM.eval(rt, "globalThis.events")
  end

  test "a server action sends what it read on entry, not what its body left", %{rt: rt} do
    {:ok, _} =
      QuickBEAM.eval(
        rt,
        ~s|document.querySelector("#a button.selected").dispatchEvent(new Event("click"))|
      )

    refute html(rt, "a") =~ "Bob"

    assert {:ok, [["removeSelected", %{"selected" => [2]}]]} =
             QuickBEAM.eval(rt, "globalThis.events.a")
  end

  test "a server action whose body returns early isn't sent", %{rt: rt} do
    click = ~s|document.querySelector("#a button").dispatchEvent(new Event("click"))|

    {:ok, _} = QuickBEAM.eval(rt, click)
    {:ok, _} = QuickBEAM.eval(rt, click)

    assert {:ok, [["remove", %{"id" => 1}]]} = QuickBEAM.eval(rt, "globalThis.events.a")
  end

  test "props applied after mount re-render that instance", %{rt: rt} do
    {:ok, _} = QuickBEAM.eval(rt, ~s|instances.b.applyProps({ users: [{ id: 3, name: "Eve" }] })|)

    assert html(rt, "b") =~ "Eve"
    refute html(rt, "b") =~ "Dan"
    assert html(rt, "a") =~ "Bob"
  end

  test "unmount removes only that instance", %{rt: rt} do
    {:ok, _} = QuickBEAM.eval(rt, "instances.a.unmount()")

    refute html(rt, "a") =~ "Ann"
    assert html(rt, "b") =~ "Cat"
  end
end
