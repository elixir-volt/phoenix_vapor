defmodule PhoenixVapor.VueRuntimeTest do
  use ExUnit.Case, async: false
  alias PhoenixVapor.VueRuntime

  @bundle_path Path.join(File.cwd!(), "priv/js/reka-dialog.js")

  setup do
    if File.regular?(@bundle_path) do
      :ok
    else
      {:skip, "reka-dialog.js bundle not found — run esbuild first"}
    end
  end

  describe "basic Vue runtime" do
    test "mounts a simple Vue app" do
      {:ok, rt} = VueRuntime.start_link(
        bundle: @bundle_path,
        setup: """
          const { createApp, ref, defineComponent, h } = Vue;
          globalThis.count = ref(0);
          createApp(defineComponent({
            setup() {
              return () => h("div", { id: "app" }, [
                h("p", "Count: " + count.value),
              ]);
            }
          })).mount(document.body);
        """
      )

      {:ok, html} = VueRuntime.render(rt)
      assert html =~ "Count: 0"

      {:ok, html} = VueRuntime.call(rt, "count.value = 42")
      assert html =~ "Count: 42"

      VueRuntime.stop(rt)
    end

    test "provide/inject between components" do
      {:ok, rt} = VueRuntime.start_link(
        bundle: @bundle_path,
        setup: """
          const { createApp, ref, computed, defineComponent, h, provide, inject } = Vue;
          globalThis.name = ref("World");
          const Child = defineComponent({
            setup() {
              const greeting = inject("greeting");
              return () => h("span", { id: "child" }, greeting.value);
            }
          });
          createApp(defineComponent({
            setup() {
              provide("greeting", computed(() => "Hello, " + name.value + "!"));
              return () => h("div", [h(Child)]);
            }
          })).mount(document.body);
        """
      )

      {:ok, html} = VueRuntime.render(rt)
      assert html =~ "Hello, World!"

      {:ok, html} = VueRuntime.call(rt, ~s(name.value = "Vue"))
      assert html =~ "Hello, Vue!"

      VueRuntime.stop(rt)
    end
  end

  describe "Reka UI Dialog" do
    test "renders with ARIA attributes" do
      {:ok, rt} = VueRuntime.start_link(
        bundle: @bundle_path,
        setup: """
          const { createApp, ref, defineComponent, h } = Vue;
          const RD = RekaDialog;
          globalThis.open = ref(false);
          createApp(defineComponent({
            setup() {
              return () => h(RD.DialogRoot, { open: open.value, "onUpdate:open": v => open.value = v }, {
                default: () => [
                  h(RD.DialogTrigger, { asChild: true }, {
                    default: () => h("button", { id: "trigger" }, "Open")
                  }),
                  h(RD.DialogPortal, null, {
                    default: () => [
                      h(RD.DialogOverlay, { class: "overlay" }),
                      h(RD.DialogContent, { class: "content" }, {
                        default: () => [h(RD.DialogTitle, null, { default: () => "Title" })]
                      })
                    ]
                  })
                ]
              });
            }
          })).mount(document.body);
        """
      )

      {:ok, closed_html} = VueRuntime.render(rt)
      assert closed_html =~ ~s(data-state="closed") or closed_html =~ "<!---->"

      {:ok, open_html} = VueRuntime.call(rt, "open.value = true")
      assert open_html =~ ~s(aria-expanded="true")
      assert open_html =~ ~s(data-state="open")
      assert open_html =~ ~s(role="dialog")
      assert open_html =~ "Title"

      {:ok, closed_again} = VueRuntime.call(rt, "open.value = false")
      assert closed_again =~ ~s(data-state="closed")

      VueRuntime.stop(rt)
    end
  end
end
