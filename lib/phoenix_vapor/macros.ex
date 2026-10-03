defmodule PhoenixVapor.Macros do
  @moduledoc false

  # Folds template expressions that call macro imports into their values at
  # compile time.
  #
  # An SFC marks a helper the server may run while compiling with an import
  # attribute, the convention Bun and unplugin-macros use:
  #
  #     import { button } from "@/ui/variants" with { type: "macro" }
  #
  # The browser imports the helper as usual. On the server, an expression
  # whose free names are all macro imports, script constants computed from
  # them, or props a parent passed as static values runs once in QuickBEAM, and
  # its result replaces the expression. Rendering then needs no JavaScript.
  #
  # A macro call that depends on anything else, such as a prop bound to an
  # assign, can't be folded and is reported.

  alias PhoenixVapor.LiveVue.EntryPlugin

  # `static_props` is nil for a template whose props are all only known when
  # rendering, such as a LiveView's. For a component instance it has the
  # `:static` prop values, the `:dynamic` prop names, and the `:declared` props;
  # a declared prop that is neither wasn't passed, so it's `undefined`.
  @type context :: %{
          file: Path.t(),
          imports: %{String.t() => map()},
          script: String.t(),
          static_props:
            %{static: %{String.t() => term()}, dynamic: MapSet.t(), declared: [String.t()]}
            | nil
        }

  @doc "Whether the imports include a macro."
  @spec any?(%{String.t() => map()}) :: boolean()
  def any?(imports), do: Enum.any?(imports, fn {_local, import} -> macro?(import) end)

  defp macro?(%{attributes: attributes}), do: attributes["type"] == "macro"

  @doc """
  Folds the macro calls in a compiled split. `runtime` is a QuickBEAM runtime
  shared across one compile, or nil to start one; the runtime in use is
  returned with the split and diagnostics, `{split, runtime, diagnostics}`.
  """
  @spec fold(map(), context(), pid() | nil) :: {map(), pid() | nil, [{atom(), String.t()}]}
  def fold(split, ctx, runtime) do
    macros = for {local, import} <- ctx.imports, macro?(import), into: %{}, do: {local, import}

    if macros == %{} do
      {split, runtime, []}
    else
      env = environment(macros, ctx)
      runtime = runtime || start_runtime()
      bundle_id = load_bundle(runtime, macros, ctx.file)
      env = Map.put(env, :bundle_id, bundle_id)

      {split, diagnostics} = map_exprs(split, [], &fold_expr(&1, &2, env, runtime))
      {split, runtime, Enum.reverse(diagnostics)}
    end
  end

  @doc "Stops a runtime `fold/3` started."
  @spec stop(pid() | nil) :: :ok
  def stop(nil), do: :ok
  def stop(runtime), do: QuickBEAM.stop(runtime)

  # ── Which names can be folded ──

  defp environment(macros, ctx) do
    macro_names = Map.keys(macros)
    consts = foldable_consts(ctx.script, macro_names, ctx.static_props)

    %{
      macros: macros,
      consts: consts,
      static_props: ctx.static_props,
      derived: MapSet.new(macro_names ++ Enum.map(consts, &elem(&1, 0)))
    }
  end

  # Top-level `const name = init` declarations whose initializer reads only
  # foldable names, in source order, so each can use the ones before it.
  defp foldable_consts(script, macro_names, static_props) do
    case OXC.parse(script, "setup.ts") do
      {:ok, %{body: body}} ->
        body
        |> Enum.flat_map(fn
          %{type: :variable_declaration, kind: kind, declarations: declarations}
          when kind in [:const, "const"] ->
            for %{id: %{type: :identifier, name: name}, init: %{} = init} <- declarations,
                do: {name, init, slice(script, init)}

          _ ->
            []
        end)
        |> Enum.reduce({MapSet.new(macro_names), []}, fn {name, init, source}, {known, acc} ->
          case classify(refs(init), known, static_props) do
            :foldable -> {MapSet.put(known, name), [{name, source} | acc]}
            _other -> {known, acc}
          end
        end)
        |> elem(1)
        |> Enum.reverse()

      _ ->
        []
    end
  end

  # Whether an expression reading `refs` reads no macro-derived name (`:none`),
  # only names known at compile time (`:foldable`), or a macro-derived name
  # together with something known only when rendering (`:dynamic`).
  defp classify(refs, known, static_props) do
    {derived?, foldable?} =
      Enum.reduce(refs, {false, true}, fn ref, {derived?, foldable?} ->
        {derived? or MapSet.member?(known, ref),
         foldable? and foldable_ref?(ref, known, static_props)}
      end)

    cond do
      not derived? -> :none
      foldable? -> :foldable
      true -> :dynamic
    end
  end

  defp foldable_ref?("props." <> prop, _known, static_props), do: known_prop?(static_props, prop)

  defp foldable_ref?(name, known, static_props),
    do: MapSet.member?(known, name) or known_prop?(static_props, name)

  defp known_prop?(nil, _prop), do: false

  defp known_prop?(%{dynamic: dynamic, declared: declared}, prop),
    do: prop in declared and not MapSet.member?(dynamic, prop)

  # The free names an expression reads. `props.x` is reported as such, so a
  # macro call can depend on one prop without depending on all of them.
  defp refs(node), do: node |> collect_refs([]) |> Enum.reverse()

  defp collect_refs(%{type: :identifier, name: name}, acc), do: [name | acc]

  defp collect_refs(
         %{
           type: :member_expression,
           object: %{type: :identifier, name: "props"},
           property: %{name: prop},
           computed: false
         },
         acc
       ),
       do: ["props." <> prop | acc]

  defp collect_refs(%{type: :member_expression, object: object, property: property} = node, acc) do
    acc = collect_refs(object, acc)
    if node[:computed], do: collect_refs(property, acc), else: acc
  end

  defp collect_refs(%{type: :property, key: key, value: value} = node, acc) do
    acc = if node[:computed], do: collect_refs(key, acc), else: acc
    collect_refs(value, acc)
  end

  # Functions in the expression bind their own names; leave them alone.
  defp collect_refs(%{type: type}, acc)
       when type in [:arrow_function_expression, :function_expression],
       do: ["(function)" | acc]

  defp collect_refs(%{} = node, acc) do
    node
    |> Map.drop([:type, :start, :end])
    |> Enum.reduce(acc, fn {_key, value}, acc -> collect_refs(value, acc) end)
  end

  defp collect_refs(list, acc) when is_list(list), do: Enum.reduce(list, acc, &collect_refs/2)
  defp collect_refs(_value, acc), do: acc

  # ── Folding ──

  defp fold_expr({:expr, source, node, _keys} = expr, diagnostics, env, runtime)
       when is_map(node) do
    case classify(refs(node), env.derived, env.static_props) do
      :none ->
        {expr, diagnostics}

      :foldable ->
        case evaluate(runtime, source, env) do
          {:ok, value} -> {{:value, value}, diagnostics}
          {:error, message} -> {expr, [{:failed, "#{source}: #{message}"} | diagnostics]}
        end

      :dynamic ->
        {expr, [{:dynamic, source} | diagnostics]}
    end
  end

  defp fold_expr(expr, diagnostics, _env, _runtime), do: {expr, diagnostics}

  defp evaluate(runtime, source, env) do
    bindings =
      Enum.map_join(env.macros, "\n", fn {local, import} ->
        module =
          "globalThis.__pv_macros[#{Jason.encode!(env.bundle_id)}][#{Jason.encode!(import.source)}]"

        case import.imported do
          :default -> "const #{local} = #{module}.default;"
          :namespace -> "const #{local} = #{module};"
          name -> "const #{local} = #{module}[#{Jason.encode!(name)}];"
        end
      end)

    static = if env.static_props, do: env.static_props.static, else: %{}
    props = Jason.encode!(static)

    prop_bindings =
      if(env.static_props, do: env.static_props.declared, else: [])
      |> Enum.reject(&(Map.has_key?(env.macros, &1) or &1 == "props"))
      |> Enum.map_join("\n", &"const #{&1} = props[#{Jason.encode!(&1)}];")

    consts = Enum.map_join(env.consts, "\n", fn {name, init} -> "const #{name} = (#{init});" end)

    code = """
    (() => {
    #{bindings}
    const props = #{props};
    #{prop_bindings}
    #{consts}
    return (#{source});
    })()
    """

    case QuickBEAM.eval_ts(runtime, code) do
      {:ok, value} ->
        if data?(value), do: {:ok, value}, else: {:error, "the result isn't data"}

      {:error, error} ->
        {:error, Exception.message(error)}
    end
  end

  defp data?(value) when is_binary(value) or is_number(value) or is_boolean(value), do: true
  defp data?(nil), do: true
  defp data?(list) when is_list(list), do: Enum.all?(list, &data?/1)

  defp data?(map) when is_map(map) and not is_struct(map),
    do: Enum.all?(map, fn {_key, value} -> data?(value) end)

  defp data?(_value), do: false

  # ── The macro modules ──

  defp start_runtime do
    {:ok, runtime} = QuickBEAM.start()
    runtime
  end

  # Bundles the file's macro imports with Volt, resolved from the SFC's
  # directory as the browser build resolves them, and loads them under an id.
  defp load_bundle(runtime, macros, file) do
    id = file
    sources = macros |> Map.values() |> Enum.map(& &1.source) |> Enum.uniq() |> Enum.with_index()

    imports =
      Enum.map_join(sources, "\n", fn {source, i} ->
        "import * as m#{i} from #{Jason.encode!(source)};"
      end)

    modules =
      Enum.map_join(sources, ", ", fn {source, i} -> "#{Jason.encode!(source)}: m#{i}" end)

    entry = """
    #{imports}
    globalThis.__pv_macros ??= {};
    globalThis.__pv_macros[#{Jason.encode!(id)}] = {#{modules}};
    """

    entry_id = Path.rootname(file) <> ".phoenix-vapor-macros.js"
    config = Volt.Config.build()

    result =
      Volt.Builder.bundle(
        entry: EntryPlugin.entry_specifier(),
        plugins: [{EntryPlugin, entry_id: entry_id, source: entry} | config.plugins],
        aliases: config.aliases,
        node_modules: find_node_modules(Path.dirname(file)),
        name: "macros",
        minify: false,
        sourcemap: false,
        code_splitting: false
      )

    with {:ok, bundle} <- result,
         {:ok, _} <- QuickBEAM.eval(runtime, bundle.code) do
      id
    else
      {:error, reason} ->
        raise CompileError,
          description:
            "can't load the macros #{inspect(Enum.map(sources, &elem(&1, 0)))} for #{file}: #{inspect(reason)}"
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

  defp slice(source, %{start: start, end: stop}), do: binary_part(source, start, stop - start)

  # ── Walking a split's expressions ──

  @doc false
  # Maps every expression in a split, threading an accumulator. A component's
  # own template, under `:component`, belongs to that component and is skipped.
  def map_exprs(%{slots: slots} = split, acc, fun) do
    {slots, acc} = Enum.map_reduce(slots, acc, &map_slot(&1, &2, fun))
    {%{split | slots: slots}, acc}
  end

  defp map_slot(%{kind: kind, values: values} = slot, acc, fun)
       when kind in [:set_text, :set_prop] do
    {values, acc} = Enum.map_reduce(values, acc, fun)
    {%{slot | values: values}, acc}
  end

  defp map_slot(%{kind: kind, value: value} = slot, acc, fun)
       when kind in [:set_html, :v_show, :v_model] do
    {value, acc} = fun.(value, acc)
    {%{slot | value: value}, acc}
  end

  defp map_slot(%{kind: :if_node} = slot, acc, fun) do
    {condition, acc} = fun.(slot.condition, acc)
    {positive, acc} = map_exprs(slot.positive, acc, fun)
    {negative, acc} = map_branch(slot.negative, acc, fun)
    {%{slot | condition: condition, positive: positive, negative: negative}, acc}
  end

  defp map_slot(%{kind: :for_node} = slot, acc, fun) do
    {source, acc} = fun.(slot.source, acc)
    {render, acc} = map_exprs(slot.render, acc, fun)
    {%{slot | source: source, render: render}, acc}
  end

  defp map_slot(%{kind: :create_component} = slot, acc, fun) do
    {props, acc} = map_props(slot.props, acc, fun)

    {slot_fns, acc} =
      Enum.map_reduce(Map.get(slot, :slots, []), acc, fn slot_fn, acc ->
        {render, acc} = map_exprs(slot_fn.render, acc, fun)
        {%{slot_fn | render: render}, acc}
      end)

    {%{slot | props: props} |> Map.put(:slots, slot_fns), acc}
  end

  defp map_slot(%{kind: :slot_outlet} = slot, acc, fun) do
    {props, acc} = map_props(slot.props, acc, fun)
    {fallback, acc} = map_branch(slot.fallback, acc, fun)
    {%{slot | props: props, fallback: fallback}, acc}
  end

  defp map_slot(%{kind: :root_attrs} = slot, acc, fun) do
    {props, acc} = map_props(slot.props, acc, fun)
    {%{slot | props: props}, acc}
  end

  defp map_slot(slot, acc, _fun), do: {slot, acc}

  defp map_props(props, acc, fun) do
    Enum.map_reduce(props, acc, fn prop, acc ->
      {values, acc} = Enum.map_reduce(prop.values, acc, fun)
      {%{prop | values: values}, acc}
    end)
  end

  defp map_branch(nil, acc, _fun), do: {nil, acc}
  defp map_branch(%{kind: _} = slot, acc, fun), do: map_slot(slot, acc, fun)
  defp map_branch(split, acc, fun), do: map_exprs(split, acc, fun)
end
