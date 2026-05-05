defmodule PhoenixVapor.LiveVue do
  @moduledoc """
  Full Vue component runtime in QuickBEAM.

  Use via: `use PhoenixVapor, file: "X.vue", runtime: :full, bundle: "..."`

  Compiles `.vue` files with Vize, bundles with Volt (resolving component
  imports as externals against the pre-loaded bundle), then runs the result
  in QuickBEAM with the full Vue runtime.

  ## Usage

      defmodule MyAppWeb.DialogLive do
        use MyAppWeb, :live_view
        use PhoenixVapor,
          file: "Dialog.vue", runtime: :full,
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
    sfc_source = File.read!(path)
    handlers = extract_handlers(sfc_source)

    # Compile SFC with Vize
    {:ok, result} = Vize.compile_sfc(sfc_source, filename: Path.basename(path))

    # Inject handler registration into the compiled setup function via AST,
    # BEFORE bundling — so the code is still parseable ES modules
    patched = inject_handler_registration(result.code, handlers)

    # Bundle with Volt: resolve imports, rewrite externals to globals
    bundled = volt_bundle(patched, path)

    # The bundled IIFE has `var _default` scoped inside.
    # Replace with globalThis assignment so we can mount after.
    setup_js =
      bundled
      |> rewrite_var_default_to_global()
      |> Kernel.<>("\nVue.createApp(globalThis.__sfc_component).mount(document.body);\n")

    {setup_js, handlers}
  end

  defp rewrite_var_default_to_global(code) do
    case OXC.parse(code, "sfc.js") do
      {:ok, ast} ->
        patches =
          OXC.collect(ast, fn
            %{type: :variable_declaration,
              declarations: [%{type: :variable_declarator, id: %{name: "_default"}, start: ds}],
              start: s, kind: kind} when kind in [:var, "var"] ->
              {:keep, %{start: s, end: ds, change: "globalThis.__sfc_component"}}

            _ ->
              :skip
          end)

        if patches == [], do: code, else: OXC.patch_string(code, patches)

      _ ->
        code
    end
  end

  defp inject_handler_registration(code, []), do: code

  defp inject_handler_registration(code, handlers) do
    {:ok, ast} = OXC.parse(code, "sfc.js")

    # Find the setup function's return position
    setup_return_pos = find_setup_return(ast)

    if setup_return_pos do
      handler_obj = Enum.map_join(handlers, ", ", fn name -> "#{name}: #{name}" end)
      inject = "globalThis.__pv_handlers = { #{handler_obj} };\n"

      OXC.patch_string(code, [
        %{start: setup_return_pos, end: setup_return_pos, change: inject}
      ])
    else
      code
    end
  end

  defp find_setup_return(ast) do
    # Find the setup FunctionExpression body span
    setup_spans =
      OXC.collect(ast, fn
        %{type: :property, key: %{name: "setup"},
          value: %{type: :function_expression, body: %{start: bs, end: be}}} ->
          {:keep, {bs, be}}
        _ ->
          :skip
      end)

    case setup_spans do
      [{setup_start, setup_end} | _] ->
        returns =
          OXC.collect(ast, fn
            %{type: :return_statement, start: s} -> {:keep, s}
            _ -> :skip
          end)

        Enum.find(returns, fn s -> s > setup_start and s < setup_end end)

      _ ->
        nil
    end
  end

  defp volt_bundle(compiled, sfc_path) do
    tmp_dir = Path.join(System.tmp_dir!(), "pv_sfc_#{:erlang.phash2(sfc_path)}")
    File.mkdir_p!(tmp_dir)

    entry_path = Path.join(tmp_dir, "entry.js")
    File.write!(entry_path, compiled)

    {:ok, build_result} =
      Volt.Builder.build(
        entry: entry_path,
        outdir: tmp_dir,
        node_modules: find_node_modules(Path.dirname(sfc_path)),
        name: "sfc",
        minify: false,
        sourcemap: false,
        hash: false,
        code_splitting: false,
        external: @external_map
      )

    bundled = File.read!(build_result.js.path)
    File.rm_rf!(tmp_dir)
    bundled
  end

  defp extract_handlers(sfc_source) do
    with {:ok, desc} <- Vize.parse_sfc(sfc_source),
         %{content: content} <- desc.script_setup || desc.script,
         {:ok, ast} <- OXC.parse(content, "setup.js") do
      OXC.collect(ast, fn
        %{type: :function_declaration, id: %{name: name}} -> {:keep, name}
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
