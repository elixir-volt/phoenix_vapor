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

  const props = defineProps(["users"])
  const note = ref("bye")

  function remove(id) {
    "use server"
    props.users = props.users.filter(u => u.id !== id)
  }
  </script>

  <template>
    <ul>
      <li v-for="u in props.users" :key="u.id">{{ u.name }}</li>
    </ul>
    <button @click="remove(1)">Remove</button>
  </template>
  """

  setup %{tmp_dir: tmp_dir} do
    rt = start_supervised!(QuickBEAM)

    %{script_setup: %{content: script}} = Vize.parse_sfc!(@sfc)
    {refs, computeds, functions, bodies, props} = PhoenixVapor.ScriptSetup.parse(script)
    classification = Classifier.classify(refs, computeds, functions, bodies, props)
    {:ok, js} = ClientCodegen.generate(@sfc, classification)

    File.write!(Path.join(tmp_dir, "component.js"), js)

    File.write!(Path.join(tmp_dir, "entry.js"), """
    import * as component from "./component.js";

    globalThis.events = [];
    component.__applyProps({ users: [{ id: 1, name: "Ann" }, { id: 2, name: "Bob" }] });
    component.__mount(document.body, {
      pushEvent: (event, params) => globalThis.events.push([event, params])
    });
    globalThis.component = component;
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

  test "mounts with the props applied before mount", %{rt: rt} do
    assert {:ok, html} = QuickBEAM.eval(rt, "document.body.innerHTML")
    assert html =~ "Ann"
    assert html =~ "Bob"
  end

  test "a server action updates props optimistically and pushes its arguments", %{rt: rt} do
    {:ok, _} =
      QuickBEAM.eval(rt, ~s|document.querySelector("button").dispatchEvent(new Event("click"))|)

    assert {:ok, html} = QuickBEAM.eval(rt, "document.body.innerHTML")
    refute html =~ "Ann"
    assert html =~ "Bob"

    assert {:ok, [["remove", %{"id" => 1}]]} = QuickBEAM.eval(rt, "globalThis.events")
  end

  test "props applied after mount re-render", %{rt: rt} do
    {:ok, _} = QuickBEAM.eval(rt, ~s|component.__applyProps({ users: [{ id: 3, name: "Cid" }] })|)

    assert {:ok, html} = QuickBEAM.eval(rt, "document.body.innerHTML")
    assert html =~ "Cid"
    refute html =~ "Bob"
  end
end
