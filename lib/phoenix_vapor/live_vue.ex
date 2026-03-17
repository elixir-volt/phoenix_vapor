defmodule PhoenixVapor.LiveVue do
  @moduledoc """
  Mount Vue component trees as LiveView pages.

  Uses `VueRuntime` to run Vue's full component runtime in QuickBEAM —
  `defineComponent`, `provide/inject`, render functions, slots, and
  third-party libraries like Reka UI.

  The server renders the Vue app into HTML via QuickBEAM's lexbor DOM.
  State mutations trigger Vue's reactive re-render, and the new HTML
  is sent through LiveView's diff protocol.

  ## Usage

      defmodule MyAppWeb.DialogLive do
        use MyAppWeb, :live_view
        use PhoenixVapor.LiveVue,
          bundle: "priv/js/reka-dialog.js",
          setup: ~s'''
            const { createApp, ref, defineComponent, h } = Vue;
            const { DialogRoot, DialogTrigger, DialogContent,
                    DialogTitle, DialogDescription, DialogClose,
                    DialogOverlay, DialogPortal } = RekaDialog;

            const open = ref(false);

            createApp(defineComponent({
              setup() {
                return () => h(DialogRoot, {
                  open: open.value,
                  "onUpdate:open": v => open.value = v
                }, { ... });
              }
            })).mount(document.body);

            globalThis.__pv_handlers = {
              toggle() { open.value = !open.value; }
            };
          '''
      end
  """

  defmacro __using__(opts) do
    bundle = Keyword.fetch!(opts, :bundle)
    setup = Keyword.fetch!(opts, :setup)

    quote do
      @__vue_bundle__ unquote(bundle)
      @__vue_setup__ unquote(setup)

      def mount(_params, _session, socket) do
        {:ok, runtime} =
          PhoenixVapor.VueRuntime.start_link(
            bundle: @__vue_bundle__,
            setup: @__vue_setup__
          )

        {:ok, html} = PhoenixVapor.VueRuntime.render(runtime)

        socket =
          socket
          |> Phoenix.Component.assign(:__vue_runtime__, runtime)
          |> Phoenix.Component.assign(:__vue_html__, html)

        {:ok, socket}
      end

      @__vue_fingerprint__ :erlang.phash2({@__vue_bundle__, @__vue_setup__})

      def render(assigns) do
        %Phoenix.LiveView.Rendered{
          static: [~s(<div data-vue-root>), ~s(</div>)],
          dynamic: fn _changed? -> [assigns[:__vue_html__] || ""] end,
          fingerprint: @__vue_fingerprint__,
          root: true
        }
      end

      def handle_event(event, params, socket) do
        runtime = socket.assigns.__vue_runtime__
        {:ok, html} = PhoenixVapor.VueRuntime.dispatch(runtime, event, params)
        {:noreply, Phoenix.Component.assign(socket, :__vue_html__, html)}
      end

      def terminate(_reason, socket) do
        if runtime = socket.assigns[:__vue_runtime__] do
          PhoenixVapor.VueRuntime.stop(runtime)
        end
      end
    end
  end
end
