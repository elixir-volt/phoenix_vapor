defmodule PhoenixVapor.Hybrid.Classifier do
  @moduledoc """
  Classifies bindings from a parsed `<script setup>` into server-owned,
  client-owned, and mixed categories using AST-based dataflow analysis.

  Given the output of `PhoenixVapor.ScriptSetup.parse/1`, determines:
  - Which props the client needs (for serialization)
  - Which functions are server actions vs client handlers
  - Which computeds are pure-client vs mixed (depend on server props)
  """

  @type binding_kind ::
          :server_prop
          | {:client_ref, initial :: String.t()}
          | :client_computed
          | {:mixed_computed, server_deps :: [String.t()], client_deps :: [String.t()]}

  @type handler_kind ::
          :client_handler
          | {:server_action, body :: String.t()}

  @type classification :: %{
          bindings: %{String.t() => binding_kind()},
          handlers: %{String.t() => handler_kind()},
          client_props: [String.t()],
          server_only_props: [String.t()]
        }

  @doc """
  Classify all bindings and handlers from a parsed script setup.

  Accepts the tuple returned by `PhoenixVapor.ScriptSetup.parse/1`.
  """
  @spec classify(
          refs :: %{String.t() => String.t()},
          computeds :: %{String.t() => String.t()},
          functions :: [String.t()],
          function_bodies :: %{String.t() => String.t()},
          props :: [String.t()]
        ) :: classification()
  def classify(refs, computeds, functions, function_bodies, props) do
    prop_set = MapSet.new(props)
    ref_set = MapSet.new(Map.keys(refs))

    bindings =
      build_bindings(props, refs, computeds, prop_set, ref_set)

    computed_set = MapSet.new(Map.keys(computeds))
    all_client = MapSet.union(ref_set, computed_set)

    handlers =
      build_handlers(functions, function_bodies, prop_set, all_client)

    client_props = compute_client_props(bindings, props)
    server_only_props = props -- client_props

    %{
      bindings: bindings,
      handlers: handlers,
      client_props: client_props,
      server_only_props: server_only_props
    }
  end

  defp build_bindings(props, refs, computeds, prop_set, ref_set) do
    prop_bindings = Map.new(props, fn p -> {p, :server_prop} end)
    ref_bindings = Map.new(refs, fn {name, init} -> {name, {:client_ref, init}} end)

    computed_bindings =
      Map.new(computeds, fn {name, expr} ->
        free = free_variables(expr)
        server_deps = free |> Enum.filter(&MapSet.member?(prop_set, &1))
        client_deps = free |> Enum.filter(&MapSet.member?(ref_set, &1))

        kind =
          if server_deps == [] do
            :client_computed
          else
            {:mixed_computed, server_deps, client_deps}
          end

        {name, kind}
      end)

    prop_bindings
    |> Map.merge(ref_bindings)
    |> Map.merge(computed_bindings)
  end

  defp build_handlers(functions, function_bodies, prop_set, _client_set) do
    Map.new(functions, fn name ->
      body = Map.get(function_bodies, name, "")

      kind =
        cond do
          has_use_server_directive?(body) ->
            {:server_action, strip_use_server(body)}

          writes_to_prop?(body, prop_set) ->
            {:server_action, body}

          true ->
            :client_handler
        end

      {name, kind}
    end)
  end

  defp has_use_server_directive?(body) do
    case OXC.parse(body, "fn.js") do
      {:ok, %{body: [%{type: :expression_statement, directive: "use server"} | _]}} ->
        true

      {:ok, %{body: [%{type: :expression_statement, expression: %{type: :literal, value: "use server"}} | _]}} ->
        true

      _ ->
        false
    end
  end

  defp strip_use_server(body) do
    case OXC.parse(body, "fn.js") do
      {:ok, %{body: [%{type: :expression_statement, end: directive_end} | _]}} ->
        body
        |> binary_part(directive_end, byte_size(body) - directive_end)
        |> String.trim_leading(";")
        |> String.trim()

      _ ->
        body
    end
  end

  defp writes_to_prop?(body, prop_set) do
    case OXC.parse(body, "fn.js") do
      {:ok, ast} ->
        assigned_names = collect_assignment_targets(ast)
        Enum.any?(assigned_names, &MapSet.member?(prop_set, &1))

      _ ->
        false
    end
  end

  defp collect_assignment_targets(ast) do
    OXC.collect(ast, fn
      %{type: :assignment_expression, left: %{type: :identifier, name: name}} ->
        {:keep, name}

      %{type: :update_expression, argument: %{type: :identifier, name: name}} ->
        {:keep, name}

      _ ->
        :skip
    end)
  end

  defp compute_client_props(bindings, props) do
    all_computed_server_deps =
      bindings
      |> Enum.flat_map(fn
        {_name, {:mixed_computed, server_deps, _}} -> server_deps
        _ -> []
      end)
      |> MapSet.new()

    Enum.filter(props, &MapSet.member?(all_computed_server_deps, &1))
  end

  @doc """
  Extract free variables from a JavaScript expression string.

  Returns the set of unbound identifiers — variable names that are not:
  - Property names in non-computed member expressions (`a.b` → only `a`)
  - Function parameters (`x => x + 1` → only free vars, not `x`)
  - Locally declared variables
  """
  @spec free_variables(String.t()) :: [String.t()]
  def free_variables(source) do
    case OXC.parse(source, "e.js") do
      {:ok, ast} ->
        walk(ast.body, MapSet.new())
        |> MapSet.to_list()
        |> Enum.sort()

      _ ->
        case OXC.parse("function __wrapper() #{source}", "e.js") do
          {:ok, ast} ->
            walk(ast.body, MapSet.new())
            |> MapSet.to_list()
            |> Enum.sort()

          _ ->
            []
        end
    end
  end

  # ── AST Walking for Free Variable Collection ──

  defp walk(%{type: :identifier, name: name}, bound) do
    if MapSet.member?(bound, name), do: MapSet.new(), else: MapSet.new([name])
  end

  defp walk(%{type: :member_expression, object: obj, property: prop, computed: computed}, bound) do
    obj_free = walk(obj, bound)
    prop_free = if computed, do: walk(prop, bound), else: MapSet.new()
    MapSet.union(obj_free, prop_free)
  end

  defp walk(%{type: type, params: params, body: body}, bound)
       when type in [:arrow_function_expression, :function_expression] do
    param_names = extract_param_names(params)
    inner_bound = Enum.reduce(param_names, bound, &MapSet.put(&2, &1))
    body_free = walk(body, inner_bound)
    MapSet.difference(body_free, MapSet.new(param_names))
  end

  defp walk(%{type: :function_declaration, id: id, params: params, body: body}, bound) do
    param_names = extract_param_names(params)
    fn_name = if id, do: [id[:name]], else: []
    inner_bound = Enum.reduce(param_names ++ fn_name, bound, &MapSet.put(&2, &1))
    body_free = walk(body, inner_bound)
    MapSet.difference(body_free, MapSet.new(param_names ++ fn_name))
  end

  defp walk(%{type: :variable_declaration, declarations: decls}, bound) do
    {free, _bound} =
      Enum.reduce(decls, {MapSet.new(), bound}, fn decl, {acc_free, acc_bound} ->
        name = get_in(decl, [:id, :name])
        new_bound = if name, do: MapSet.put(acc_bound, name), else: acc_bound
        init_free = if decl[:init], do: walk(decl[:init], new_bound), else: MapSet.new()
        {MapSet.union(acc_free, init_free), new_bound}
      end)

    free
  end

  defp walk(%{type: :binary_expression, left: l, right: r}, bound) do
    MapSet.union(walk(l, bound), walk(r, bound))
  end

  defp walk(%{type: :logical_expression, left: l, right: r}, bound) do
    MapSet.union(walk(l, bound), walk(r, bound))
  end

  defp walk(%{type: :assignment_expression, left: l, right: r}, bound) do
    MapSet.union(walk(l, bound), walk(r, bound))
  end

  defp walk(%{type: :call_expression, callee: callee, arguments: args}, bound) do
    MapSet.union(walk(callee, bound), walk(args, bound))
  end

  defp walk(%{type: :conditional_expression, test: t, consequent: c, alternate: a}, bound) do
    [walk(t, bound), walk(c, bound), walk(a, bound)]
    |> Enum.reduce(MapSet.new(), &MapSet.union/2)
  end

  defp walk(%{type: :unary_expression, argument: arg}, bound), do: walk(arg, bound)
  defp walk(%{type: :update_expression, argument: arg}, bound), do: walk(arg, bound)
  defp walk(%{type: :expression_statement, expression: expr}, bound), do: walk(expr, bound)
  defp walk(%{type: :return_statement, argument: arg}, bound), do: if(arg, do: walk(arg, bound), else: MapSet.new())
  defp walk(%{type: :block_statement, body: body}, bound), do: walk_block(body, bound)
  defp walk(%{type: :template_literal, expressions: exprs}, bound), do: walk(exprs || [], bound)
  defp walk(%{type: :array_expression, elements: elems}, bound), do: walk(elems || [], bound)
  defp walk(%{type: :object_expression, properties: props}, bound), do: walk(props || [], bound)
  defp walk(%{type: :property, value: v}, bound), do: walk(v, bound)
  defp walk(%{type: :spread_element, argument: arg}, bound), do: walk(arg, bound)
  defp walk(%{type: :sequence_expression, expressions: exprs}, bound), do: walk(exprs, bound)
  defp walk(%{type: :parenthesized_expression, expression: expr}, bound), do: walk(expr, bound)
  defp walk(%{type: :await_expression, argument: arg}, bound), do: walk(arg, bound)
  defp walk(%{type: :yield_expression, argument: arg}, bound), do: if(arg, do: walk(arg, bound), else: MapSet.new())
  defp walk(%{type: :new_expression, callee: c, arguments: args}, bound), do: MapSet.union(walk(c, bound), walk(args, bound))
  defp walk(%{type: :tagged_template_expression, tag: tag, quasi: q}, bound), do: MapSet.union(walk(tag, bound), walk(q, bound))

  defp walk(%{type: :if_statement, test: t, consequent: c, alternate: a}, bound) do
    [walk(t, bound), walk(c, bound), if(a, do: walk(a, bound), else: MapSet.new())]
    |> Enum.reduce(MapSet.new(), &MapSet.union/2)
  end

  defp walk(%{type: :for_statement, init: init, test: test, update: update, body: body}, bound) do
    [
      if(init, do: walk(init, bound), else: MapSet.new()),
      if(test, do: walk(test, bound), else: MapSet.new()),
      if(update, do: walk(update, bound), else: MapSet.new()),
      walk(body, bound)
    ]
    |> Enum.reduce(MapSet.new(), &MapSet.union/2)
  end

  defp walk(%{type: :for_in_statement, left: l, right: r, body: body}, bound) do
    [walk(l, bound), walk(r, bound), walk(body, bound)]
    |> Enum.reduce(MapSet.new(), &MapSet.union/2)
  end

  defp walk(%{type: :for_of_statement, left: l, right: r, body: body}, bound) do
    [walk(l, bound), walk(r, bound), walk(body, bound)]
    |> Enum.reduce(MapSet.new(), &MapSet.union/2)
  end

  defp walk(%{type: :while_statement, test: t, body: body}, bound) do
    MapSet.union(walk(t, bound), walk(body, bound))
  end

  defp walk(%{type: :do_while_statement, test: t, body: body}, bound) do
    MapSet.union(walk(t, bound), walk(body, bound))
  end

  defp walk(%{type: :switch_statement, discriminant: d, cases: cases}, bound) do
    d_free = walk(d, bound)
    cases_free = Enum.reduce(cases, MapSet.new(), fn c, acc ->
      test_free = if c[:test], do: walk(c[:test], bound), else: MapSet.new()
      body_free = walk(c[:consequent] || [], bound)
      acc |> MapSet.union(test_free) |> MapSet.union(body_free)
    end)
    MapSet.union(d_free, cases_free)
  end

  defp walk(%{type: :try_statement, block: b, handler: h, finalizer: f}, bound) do
    [
      walk(b, bound),
      if(h, do: walk(h[:body], bound), else: MapSet.new()),
      if(f, do: walk(f, bound), else: MapSet.new())
    ]
    |> Enum.reduce(MapSet.new(), &MapSet.union/2)
  end

  defp walk(%{type: :throw_statement, argument: arg}, bound), do: walk(arg, bound)

  defp walk(%{type: type}, _bound)
       when type in [:literal, :program, :empty_statement, :break_statement,
                     :continue_statement, :debugger_statement, :this_expression,
                     :super, :import_expression, :meta_property] do
    MapSet.new()
  end

  # Catch-all for unhandled node types — safe default
  defp walk(%{type: _}, _bound), do: MapSet.new()

  defp walk(list, bound) when is_list(list) do
    Enum.reduce(list, MapSet.new(), fn item, acc -> MapSet.union(acc, walk(item, bound)) end)
  end

  defp walk(nil, _bound), do: MapSet.new()
  defp walk(_, _bound), do: MapSet.new()

  defp walk_block(stmts, bound) when is_list(stmts) do
    {free, _} =
      Enum.reduce(stmts, {MapSet.new(), bound}, fn stmt, {acc_free, acc_bound} ->
        case stmt do
          %{type: :variable_declaration, declarations: decls} ->
            {decl_free, new_bound} =
              Enum.reduce(decls, {MapSet.new(), acc_bound}, fn decl, {df, db} ->
                name = get_in(decl, [:id, :name])
                new_db = if name, do: MapSet.put(db, name), else: db
                init_free = if decl[:init], do: walk(decl[:init], new_db), else: MapSet.new()
                {MapSet.union(df, init_free), new_db}
              end)

            {MapSet.union(acc_free, decl_free), new_bound}

          _ ->
            stmt_free = walk(stmt, acc_bound)
            {MapSet.union(acc_free, stmt_free), acc_bound}
        end
      end)

    free
  end

  defp walk_block(nil, _bound), do: MapSet.new()

  defp extract_param_names(params) when is_list(params) do
    Enum.flat_map(params, fn
      %{type: :identifier, name: name} -> [name]
      %{type: :assignment_pattern, left: %{type: :identifier, name: name}} -> [name]
      %{type: :rest_element, argument: %{type: :identifier, name: name}} -> [name]
      %{type: :object_pattern, properties: props} ->
        Enum.flat_map(props, fn
          %{value: %{type: :identifier, name: name}} -> [name]
          %{type: :identifier, name: name} -> [name]
          _ -> []
        end)
      %{type: :array_pattern, elements: elems} ->
        Enum.flat_map(elems || [], fn
          %{type: :identifier, name: name} -> [name]
          _ -> []
        end)
      _ -> []
    end)
  end

  defp extract_param_names(_), do: []
end
