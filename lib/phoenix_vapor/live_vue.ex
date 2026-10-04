defmodule PhoenixVapor.LiveVue do
  @moduledoc """
  Full Vue component runtime in QuickBEAM.

  Use via: `use PhoenixVapor, file: "X.vue", runtime: :full, bundle: "..."`

  Compiles `.vue` files with Vize, bundles with Volt (resolving component
  imports as externals against the pre-loaded bundle), then runs the result
  in QuickBEAM with the full Vue runtime.

  The generated LiveView callbacks are overridable. Host LiveViews can retain
  their own lifecycle behavior and call `super/3`, `super/1`, or `super/2` to
  compose it with the full Vue runtime:

      def mount(params, session, socket) do
        {:ok, socket} = super(params, session, socket)
        {:ok, assign_async(socket, :account, &load_account/0)}
      end

      def handle_event("host-event", params, socket) do
        # Handle host-owned events without dispatching them to Vue.
        {:noreply, handle_host_event(params, socket)}
      end

      def handle_event(event, params, socket), do: super(event, params, socket)

  ## Usage

      defmodule MyAppWeb.DialogLive do
        use MyAppWeb, :live_view
        use PhoenixVapor,
          file: "Dialog.vue", runtime: :full,
          bundle: "priv/js/reka-dialog.js",
          globals: %{"reka-ui" => "RekaDialog"}
      end

  ## Options

    * `:bundle` — path to a script that defines the component libraries as
      globals, such as one built with `mix phoenix_vapor.bundle`. It is read
      once and cached until the file changes.
    * `:globals` — the global each imported package is available as in the
      bundle. `vue` is always `Vue`.
  """

  @default_globals %{"vue" => "Vue"}

  defmacro __using__(opts) do
    bundle = Keyword.fetch!(opts, :bundle)
    full_path = opts |> Keyword.fetch!(:file) |> PhoenixVapor.SFC.path!(__CALLER__)

    {globals, _binding} = opts |> Keyword.get(:globals, Macro.escape(%{})) |> Code.eval_quoted()
    globals = Map.merge(@default_globals, globals)
    {setup_js, handlers} = compile_sfc(full_path, globals)
    escaped_handlers = Macro.escape(handlers)

    quote do
      @__vue_bundle__ unquote(bundle)
      @__vue_setup__ unquote(setup_js)
      @__vue_handlers__ unquote(escaped_handlers)
      @__vue_fingerprint__ :erlang.phash2({@__vue_bundle__, @__vue_setup__})
      @external_resource unquote(full_path)

      def mount(_params, _session, socket) do
        runtime =
          PhoenixVapor.LiveVue.unwrap!(
            PhoenixVapor.VueRuntime.start_link(bundle: @__vue_bundle__, setup: @__vue_setup__)
          )

        html = PhoenixVapor.LiveVue.unwrap!(PhoenixVapor.VueRuntime.render(runtime))

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

        html =
          PhoenixVapor.LiveVue.unwrap!(PhoenixVapor.VueRuntime.dispatch(runtime, event, params))

        {:noreply, Phoenix.Component.assign(socket, :__vue_html__, html)}
      end

      def terminate(_reason, socket) do
        if runtime = socket.assigns[:__vue_runtime__] do
          PhoenixVapor.VueRuntime.stop(runtime)
        end
      end

      defoverridable mount: 3, render: 1, handle_event: 3, terminate: 2
    end
  end

  @doc """
  Returns the value of a `PhoenixVapor.VueRuntime` result, or raises its
  error. Generated callbacks use it so a JavaScript exception surfaces as
  itself rather than as a `MatchError`.
  """
  @spec unwrap!({:ok, value} | {:error, term()}) :: value when value: term()
  def unwrap!({:ok, value}), do: value
  def unwrap!({:error, error}) when is_exception(error), do: raise(error)
  def unwrap!({:error, reason}), do: raise("PhoenixVapor.VueRuntime failed: #{inspect(reason)}")

  @doc false
  def compile_sfc(path, globals \\ @default_globals) do
    sfc_source = path |> File.read!() |> PhoenixVapor.SFC.without_elixir_block()
    handlers = extract_handlers(sfc_source)

    # Compile SFC with Vize
    {:ok, result} = Vize.compile_sfc(sfc_source, filename: Path.basename(path))

    # Inject handler registration into the compiled setup function via AST,
    # BEFORE bundling — so the code is still parseable ES modules
    patched = inject_handler_registration(result.code, handlers)

    # Bundle with Volt: resolve imports, rewrite externals to globals
    bundled = volt_bundle(patched, path, globals)

    # Capture the value returned by Volt's bundled IIFE so it can be mounted.
    setup_js =
      bundled
      |> assign_bundle_result_to_global()
      |> Kernel.<>("\nVue.createApp(globalThis.__sfc_component).mount(document.body);\n")

    {setup_js, handlers}
  end

  defp assign_bundle_result_to_global(code) do
    case OXC.parse(code, "sfc.js") do
      {:ok,
       %{
         type: :program,
         body: [
           %{type: :expression_statement, expression: %{type: :call_expression, start: start}}
           | _
         ]
       }} ->
        OXC.patch_string(code, [
          PhoenixVapor.JS.patch(start, start, "globalThis.__sfc_component = ")
        ])

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
        PhoenixVapor.JS.patch(setup_return_pos, setup_return_pos, inject)
      ])
    else
      code
    end
  end

  defp find_setup_return(ast) do
    # Find the setup FunctionExpression body span
    setup_spans =
      OXC.collect(ast, fn
        %{
          type: :property,
          key: %{name: "setup"},
          value: %{type: :function_expression, body: %{start: bs, end: be}}
        } ->
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

  defp volt_bundle(compiled, sfc_path, globals) do
    case PhoenixVapor.JS.bundle(compiled, sfc_path, name: "sfc", minify: false, external: globals) do
      {:ok, code} -> code
      {:error, reason} -> raise "Failed to bundle #{sfc_path}: #{reason}"
    end
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
end
