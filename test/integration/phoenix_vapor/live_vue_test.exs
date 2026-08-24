defmodule PhoenixVapor.Integration.LiveVueTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  test "assigns the bundled component export before mounting" do
    {setup, handlers} =
      PhoenixVapor.LiveVue.compile_sfc("test/fixtures/Probe.vue")

    assert handlers == []
    assert setup =~ "globalThis.__sfc_component = (function()"
    assert setup =~ "Vue.createApp(globalThis.__sfc_component).mount(document.body)"
  end

  test "resolves sibling Vue imports from the source component directory" do
    {setup, handlers} =
      PhoenixVapor.LiveVue.compile_sfc("test/fixtures/Parent.vue")

    assert handlers == []
    assert setup =~ "child component"
    refute setup =~ System.tmp_dir!()
  end
end
