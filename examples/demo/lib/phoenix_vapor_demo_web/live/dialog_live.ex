defmodule PhoenixVaporDemoWeb.DialogLive do
  use PhoenixVaporDemoWeb, :live_view

  use PhoenixVapor.LiveVue,
    bundle: "priv/js/reka-dialog.js",
    setup: """
      const { createApp, ref, defineComponent, h } = globalThis.Vue;
      const RD = globalThis.RekaDialog;

      const open = ref(false);

      createApp(defineComponent({
        setup() {
          return () => h("div", { class: "space-y-4" }, [
            h("h2", { class: "text-2xl font-bold" }, "Reka UI Dialog"),
            h("p", { class: "text-sm text-gray-500" },
              "Server-side rendered Vue component library via QuickBEAM. " +
              "Full ARIA attributes, reactive state, provide/inject — all running on the BEAM."),

            h(RD.DialogRoot, {
              open: open.value,
              "onUpdate:open": v => open.value = v
            }, {
              default: () => [
                h(RD.DialogTrigger, { asChild: true }, {
                  default: () => h("button", {
                    class: "px-4 py-2 bg-indigo-600 text-white rounded hover:bg-indigo-700"
                  }, "Open Dialog")
                }),
                h(RD.DialogPortal, null, {
                  default: () => [
                    h(RD.DialogOverlay, {
                      class: "fixed inset-0 bg-black/50",
                      style: open.value ? "" : "display:none"
                    }),
                    h(RD.DialogContent, {
                      class: "fixed top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 bg-white rounded-lg p-6 shadow-xl max-w-md w-full",
                      style: open.value ? "" : "display:none"
                    }, {
                      default: () => [
                        h(RD.DialogTitle, { class: "text-lg font-semibold" }, {
                          default: () => "Edit Profile"
                        }),
                        h(RD.DialogDescription, { class: "text-sm text-gray-500 mt-1" }, {
                          default: () => "Make changes to your profile here."
                        }),
                        h("div", { class: "mt-4 space-y-3" }, [
                          h("input", {
                            type: "text",
                            placeholder: "Name",
                            class: "w-full px-3 py-2 border rounded"
                          }),
                          h("input", {
                            type: "email",
                            placeholder: "Email",
                            class: "w-full px-3 py-2 border rounded"
                          }),
                        ]),
                        h("div", { class: "mt-4 flex justify-end gap-2" }, [
                          h(RD.DialogClose, { asChild: true }, {
                            default: () => h("button", {
                              class: "px-4 py-2 bg-gray-200 rounded hover:bg-gray-300"
                            }, "Cancel")
                          }),
                          h(RD.DialogClose, { asChild: true }, {
                            default: () => h("button", {
                              class: "px-4 py-2 bg-indigo-600 text-white rounded hover:bg-indigo-700"
                            }, "Save Changes")
                          }),
                        ]),
                      ]
                    })
                  ]
                })
              ]
            }),

            h("p", { class: "text-xs text-gray-400 mt-4" },
              "Dialog state: " + (open.value ? "open" : "closed") +
              " · ARIA attributes rendered server-side · No client-side JavaScript")
          ]);
        }
      })).mount(document.body);

      globalThis.__pv_handlers = {
        toggle() { open.value = !open.value; }
      };
    """
end
