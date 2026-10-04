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
  # A macro call that reads props known only when rendering runs once for each
  # combination of the values their TypeScript types allow, such as a variant
  # prop's literals, up to 64 combinations; rendering looks the result up. A
  # macro call that depends on anything else, such as a prop typed `string`,
  # can't be folded and is reported.

  alias PhoenixVapor.{PropTypes, Template}

  @max_combinations 64

  # `static_props` is nil for a template whose props are all only known when
  # rendering, such as a LiveView's. For a component instance it has the
  # `:static` prop values, the `:dynamic` prop names, and the `:declared` props;
  # a declared prop that is neither wasn't passed, so it's `undefined`.
  @type context :: %{
          optional(:known) => %{String.t() => term()},
          optional(:elixir) => {module(), map()} | nil,
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
  @spec fold(Template.t(), context(), pid() | nil) :: {Template.t(), pid() | nil, [map()]}
  def fold(split, ctx, runtime) do
    macros = for {local, import} <- ctx.imports, macro?(import), into: %{}, do: {local, import}

    if macros == %{} do
      {split, runtime, []}
    else
      env = environment(macros, ctx)
      runtime = runtime || start_runtime()
      bundle_id = load_bundle(runtime, macros, ctx.file)
      env = Map.put(env, :bundle_id, bundle_id)

      env = Map.merge(env, %{file: ctx.file, script: ctx.script})
      {split, diagnostics} = Template.map_exprs(split, [], &fold_expr(&1, &2, &3, env, runtime))
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

  defp fold_expr({:expr, source, node, _keys} = expr, slot, diagnostics, env, runtime)
       when is_map(node) do
    case classify(refs(node), env.derived, env.static_props) do
      :none ->
        {expr, diagnostics}

      :foldable ->
        case evaluate(runtime, source, env) do
          {:ok, value} ->
            {{:value, value}, diagnostics}

          {:error, message} ->
            {expr,
             [
               diagnostic(env, slot, :error, "the macro call `#{source}` failed: #{message}")
               | diagnostics
             ]}
        end

      :dynamic ->
        case expand(node, source, env, runtime) do
          {:ok, lookup} ->
            {lookup, diagnostics}

          {:error, reason} ->
            message =
              "`#{source}` calls a macro with values known only when rendering: #{reason}"

            {{:unrendered, source}, [diagnostic(env, slot, :unrendered, message) | diagnostics]}
        end
    end
  end

  defp fold_expr(expr, _slot, diagnostics, _env, _runtime), do: {expr, diagnostics}

  # Runs the call for each combination of the values its props known only
  # when rendering can take, as their types declare them.
  defp expand(node, source, env, runtime) do
    props =
      node
      |> refs()
      |> Enum.reject(&foldable_ref?(&1, env.derived, env.static_props))
      |> Enum.map(&prop_name/1)
      |> Enum.uniq()

    with {:ok, domains} <- PropTypes.literal_values(runtime, env.file, env.script, props),
         {:ok, combinations} <- combinations(props, domains) do
      Enum.reduce_while(combinations, {:ok, %{}}, fn values, {:ok, table} ->
        case evaluate(runtime, source, with_props(env, props, values)) do
          {:ok, value} -> {:cont, {:ok, Map.put(table, values, value)}}
          {:error, message} -> {:halt, {:error, "with #{inspect(values)} it failed: #{message}"}}
        end
      end)
      |> case do
        {:ok, table} -> {:ok, {:lookup, source, props, table}}
        error -> error
      end
    end
  end

  defp prop_name("props." <> prop), do: prop
  defp prop_name(name), do: name

  defp combinations(props, domains) do
    case Enum.find(props, &(domains[&1] == nil)) do
      nil ->
        combinations =
          Enum.reduce(Enum.reverse(props), [[]], &for(v <- domains[&1], c <- &2, do: [v | c]))

        if length(combinations) <= @max_combinations,
          do: {:ok, combinations},
          else:
            {:error,
             "its props can take #{length(combinations)} combinations of values, more than #{@max_combinations}"}

      prop ->
        {:error, "the type of `#{prop}` isn't a set of literal values"}
    end
  end

  # The environment with `props` known to have `values`; a nil value is a prop
  # that wasn't passed, so it's `undefined`.
  defp with_props(env, props, values) do
    static_props = env.static_props || %{static: %{}, dynamic: MapSet.new(), declared: []}

    static =
      props
      |> Enum.zip(values)
      |> Enum.reject(fn {_prop, value} -> value == nil end)
      |> Map.new()
      |> then(&Map.merge(Map.drop(static_props.static, props), &1))

    %{
      env
      | static_props: %{
          static_props
          | static: static,
            dynamic: MapSet.difference(static_props.dynamic, MapSet.new(props)),
            declared: Enum.uniq(static_props.declared ++ props)
        }
    }
  end

  defp diagnostic(env, slot, severity, message),
    do: %{file: env.file, severity: severity, message: message, position: slot[:position] || 0}

  defp evaluate(runtime, source, env) do
    {static, declared} =
      case env.static_props do
        nil -> {%{}, []}
        %{static: static, declared: declared} -> {static, declared}
      end

    macro_bindings =
      for {local, import} <- env.macros do
        "const #{local} = #{macro_access(env.bundle_id, import)};"
      end

    prop_bindings =
      for name <- declared, not Map.has_key?(env.macros, name), name != "props" do
        "const #{name} = props[#{Jason.encode!(name)}];"
      end

    const_bindings = for {name, init} <- env.consts, do: "const #{name} = (#{init});"

    code =
      PhoenixVapor.JS.template!("macro-call.ts", [result: {:expr, source}],
        bindings: macro_bindings ++ prop_bindings ++ const_bindings
      )

    case QuickBEAM.eval_ts(runtime, code, vars: %{"props" => static}) do
      {:ok, value} ->
        if data?(value), do: {:ok, value}, else: {:error, "the result isn't data"}

      {:error, error} ->
        {:error, Exception.message(error)}
    end
  end

  defp macro_access(bundle_id, %{source: source, imported: imported}) do
    module = "globalThis.__pv_macros[#{Jason.encode!(bundle_id)}][#{Jason.encode!(source)}]"

    case imported do
      :default -> module <> ".default"
      :namespace -> module
      name -> "#{module}[#{Jason.encode!(name)}]"
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
    {:ok, runtime} = QuickBEAM.start(handlers: PropTypes.handlers())
    runtime
  end

  # Bundles the file's macro imports with Volt, resolved from the SFC's
  # directory as the browser build resolves them, and loads them under an id.
  defp load_bundle(runtime, macros, file) do
    sources = macros |> Map.values() |> Enum.map(& &1.source) |> Enum.uniq()
    {imports, modules} = PhoenixVapor.JS.module_splices(sources)

    entry =
      Volt.Priv.render!({:phoenix_vapor, "ts"}, "macro-entry.ts", [id: file],
        splices: [imports: imports, modules: modules]
      )

    with {:ok, code} <- PhoenixVapor.JS.bundle(entry, file, name: "macros", minify: false),
         {:ok, _} <- QuickBEAM.eval(runtime, code) do
      file
    else
      {:error, reason} ->
        raise CompileError,
          description:
            "can't load the macros #{inspect(sources)} for #{file}: " <>
              PhoenixVapor.JS.error_message(reason)
    end
  end

  defp slice(source, %{start: start, end: stop}), do: binary_part(source, start, stop - start)
end
