defmodule LiveVueNext.ScriptSetup do
  @moduledoc """
  Extracts reactive state and functions from `<script setup>` blocks.

  Parses the script with OXC and evaluates initial state in QuickBEAM.
  The resulting state map becomes LiveView assigns, and functions become
  event handlers.

  ## Architecture

  Instead of running Vue's full reactive system, we take a pragmatic approach:

  - `ref(value)` → extracted as initial assign value
  - `computed(() => expr)` → extracted as a derived assign (re-evaluated on change)
  - `defineProps([...])` → maps directly to LiveView assigns
  - Functions → mapped to `handle_event` callbacks
  - `ref.value` access in templates → already handled by Expr evaluator

  This gives us 90% of `<script setup>` ergonomics without needing the Vue
  reactive runtime on the server.
  """

  @doc """
  Parse a `<script setup>` block and extract initial state + event handlers.

  Returns `{initial_assigns, computed_exprs, event_handlers}`.
  """
  def parse(script_source) do
    case OXC.parse(script_source, "setup.js") do
      {:ok, ast} ->
        refs = extract_refs(ast)
        computeds = extract_computeds(ast)
        functions = extract_functions(ast)
        props = extract_props(ast)
        {refs, computeds, functions, props}

      _ ->
        {%{}, %{}, %{}, []}
    end
  end

  @doc """
  Evaluate initial state from refs using QuickBEAM.

  Converts `ref(0)` → `%{count: 0}`, etc.
  """
  def eval_initial_state(refs, assigns \\ %{}) do
    if Code.ensure_loaded?(QuickBEAM) do
      {:ok, rt} = QuickBEAM.start()

      Enum.reduce(refs, assigns, fn {name, init_expr}, acc ->
        case QuickBEAM.eval(rt, "(#{init_expr})") do
          {:ok, value} -> Map.put(acc, String.to_atom(name), value)
          _ -> Map.put(acc, String.to_atom(name), nil)
        end
      end)
    else
      Enum.reduce(refs, assigns, fn {name, _}, acc ->
        Map.put(acc, String.to_atom(name), nil)
      end)
    end
  end

  @doc """
  Evaluate computed expressions against current assigns.
  """
  def eval_computeds(computeds, assigns) do
    Enum.reduce(computeds, assigns, fn {name, expr}, acc ->
      value = LiveVueNext.Expr.eval(expr, acc)
      Map.put(acc, String.to_atom(name), value)
    end)
  end

  defp extract_refs(ast) do
    OXC.collect(ast, fn
      %{type: "VariableDeclaration", declarations: decls} ->
        refs =
          for %{type: "VariableDeclarator", id: %{name: name}, init: init} <- decls,
              init != nil,
              %{type: "CallExpression", callee: %{name: "ref"}, arguments: args} <- [init],
              [arg | _] <- [args] do
            {name, source_text(arg)}
          end

        case refs do
          [] -> :skip
          _ -> {:keep, refs}
        end

      _ ->
        :skip
    end)
    |> List.flatten()
    |> Map.new()
  end

  defp extract_computeds(ast) do
    OXC.collect(ast, fn
      %{type: "VariableDeclaration", declarations: decls} ->
        computeds =
          for %{type: "VariableDeclarator", id: %{name: name}, init: init} <- decls,
              init != nil,
              %{type: "CallExpression", callee: %{name: "computed"}, arguments: args} <- [init],
              [%{type: "ArrowFunctionExpression", body: body} | _] <- [args] do
            expr =
              case body do
                %{type: "BlockStatement"} -> nil
                expr_node -> source_text(expr_node)
              end

            if expr, do: {name, expr}
          end

        case Enum.filter(computeds, & &1) do
          [] -> :skip
          found -> {:keep, found}
        end

      _ ->
        :skip
    end)
    |> List.flatten()
    |> Map.new()
  end

  defp extract_functions(ast) do
    OXC.collect(ast, fn
      %{type: "FunctionDeclaration", id: %{name: name}} ->
        {:keep, name}

      _ ->
        :skip
    end)
  end

  defp extract_props(ast) do
    OXC.collect(ast, fn
      %{type: "ExpressionStatement",
        expression: %{type: "CallExpression", callee: %{name: "defineProps"}, arguments: args}} ->
        case args do
          [%{type: "ArrayExpression", elements: elements}] ->
            props = for %{type: "Literal", value: v} <- elements, do: v
            {:keep, props}

          _ ->
            :skip
        end

      _ ->
        :skip
    end)
    |> List.flatten()
  end

  defp source_text(%{start: s, end: e} = node) do
    case Map.get(node_map(), {s, e}) do
      nil -> inspect_node_value(node)
      text -> text
    end
  end

  defp source_text(_), do: "null"

  defp inspect_node_value(%{type: "Literal", value: v}) when is_number(v), do: to_string(v)
  defp inspect_node_value(%{type: "Literal", value: v}) when is_binary(v), do: inspect(v)
  defp inspect_node_value(%{type: "Literal", raw: raw}), do: raw
  defp inspect_node_value(%{type: "ArrayExpression"}), do: "[]"
  defp inspect_node_value(%{type: "ObjectExpression"}), do: "{}"
  defp inspect_node_value(%{type: "Identifier", name: n}), do: n
  defp inspect_node_value(%{type: "BinaryExpression", left: l, operator: op, right: r}),
    do: "#{inspect_node_value(l)} #{op} #{inspect_node_value(r)}"
  defp inspect_node_value(%{type: "MemberExpression", object: obj, property: prop}),
    do: "#{inspect_node_value(obj)}.#{inspect_node_value(prop)}"
  defp inspect_node_value(_), do: "null"

  defp node_map, do: %{}
end
