defmodule PhoenixVapor.LiveVue do
  @moduledoc """
  Mount Vue SFC files as LiveView pages with full component runtime.

  Compiles `.vue` files with Vize, bundles with Volt (resolving component
  imports as externals against the pre-loaded bundle), then runs the result
  in QuickBEAM with the full Vue runtime.

  ## Usage

      defmodule MyAppWeb.DialogLive do
        use MyAppWeb, :live_view
        use PhoenixVapor.LiveVue,
          file: "Dialog.vue",
          bundle: "priv/js/reka-dialog.js"
      end
  """

  @external_map %{
    "vue" => "Vue",
    "reka-ui" => "RekaDialog",
    "@vueuse/core" => "VueUse",
    "@vueuse/shared" => "VueUseShared"
  }

  defmacro __using__(opts) do
    bundle = Keyword.fetch!(opts, :bundle)
    file = Keyword.fetch!(opts, :file)
    caller_dir = __CALLER__.file |> Path.dirname()
    full_path = Path.expand(file, caller_dir)

    {setup_js, handlers} = compile_sfc(full_path)
    escaped_handlers = Macro.escape(handlers)

    quote do
      @__vue_bundle__ unquote(bundle)
      @__vue_setup__ unquote(setup_js)
      @__vue_handlers__ unquote(escaped_handlers)
      @__vue_fingerprint__ :erlang.phash2({@__vue_bundle__, @__vue_setup__})
      @external_resource unquote(full_path)

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

  @doc false
  def compile_sfc(path) do
    # Write compiled SFC to a temp file so Volt.Builder can process it
    sfc_source = File.read!(path)
    handlers = extract_handlers(sfc_source)

    dir = System.tmp_dir!()
    tmp_dir = Path.join(dir, "phoenix_vapor_sfc_#{:erlang.phash2(path)}")
    File.mkdir_p!(tmp_dir)

    # Vize compiles the SFC into JS with import statements
    {:ok, result} = Vize.compile_sfc(sfc_source, filename: Path.basename(path))
    entry_path = Path.join(tmp_dir, "entry.js")
    File.write!(entry_path, result.code)

    # Detect node_modules from the SFC's directory
    node_modules = find_node_modules(Path.dirname(path))

    # Volt.Builder compiles + bundles with externals resolved to globals
    {:ok, build_result} =
      Volt.Builder.build(
        entry: entry_path,
        outdir: tmp_dir,
        node_modules: node_modules,
        name: "sfc",
        minify: false,
        sourcemap: false,
        hash: false,
        code_splitting: false,
        external: @external_map
      )

    compiled = File.read!(build_result.js.path)

    # Wrap in IIFE that mounts the app and registers handlers
    setup_js = wrap_setup(compiled, handlers)

    # Cleanup
    File.rm_rf!(tmp_dir)

    {setup_js, handlers}
  end

  defp wrap_setup(compiled, handlers) do
    # Inject handler registration into the SFC's setup function.
    # The compiled code has: setup(__props) { ... return (render fn) }
    # We inject `globalThis.__pv_handlers = { toggle, ... }` before the return.

    handler_obj =
      handlers
      |> Enum.map_join(", ", fn name -> "#{name}: #{name}" end)

    inject = "globalThis.__pv_handlers = { #{handler_obj} };"

    # Find "return (_ctx" in the setup function and inject before it
    patched =
      compiled
      |> String.replace("var _default =", "globalThis.__sfc_component =")
      |> String.replace(
        ~r/return \(_ctx/,
        "#{inject}\n\t\t\treturn (_ctx"
      )

    """
    #{patched}
    Vue.createApp(globalThis.__sfc_component).mount(document.body);
    """
  end

  defp extract_handlers(sfc_source) do
    with {:ok, desc} <- Vize.parse_sfc(sfc_source),
         %{content: content} <- desc.script_setup || desc.script,
         {:ok, ast} <- OXC.parse(content, "setup.js") do
      OXC.collect(ast, fn
        %{type: "FunctionDeclaration", id: %{name: name}} -> {:keep, name}
        _ -> :skip
      end)
    else
      _ -> []
    end
  end

  defp find_node_modules(dir) do
    candidate = Path.join(dir, "node_modules")

    cond do
      File.dir?(candidate) -> candidate
      dir == "/" -> nil
      true -> find_node_modules(Path.dirname(dir))
    end
  end
end
