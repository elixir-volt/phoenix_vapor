defmodule PhoenixVapor.LiveVueTest do
  use ExUnit.Case, async: true

  test "assigns the bundled component export before mounting" do
    {setup, handlers} =
      PhoenixVapor.LiveVue.compile_sfc("test/fixtures/Probe.vue")

    assert handlers == []
    assert setup =~ "globalThis.__sfc_component = (function()"
    assert setup =~ "Vue.createApp(globalThis.__sfc_component).mount(document.body)"
  end
end
