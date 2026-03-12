defmodule PhoenixVapor.ScriptSetup do
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
        refs = extract_refs(ast, script_source)
        computeds = extract_computeds(ast, script_source)
        functions = extract_functions(ast)
        function_bodies = extract_function_bodies(ast, script_source)
        props = extract_props(ast)
        {refs, computeds, functions, function_bodies, props}

      _ ->
        {%{}, %{}, %{}, %{}, []}
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
      value = PhoenixVapor.Expr.eval(expr, acc)
      Map.put(acc, String.to_atom(name), value)
    end)
  end

  defp extract_refs(ast, source) do
    OXC.collect(ast, fn
      %{type: "VariableDeclaration", declarations: decls} ->
        refs =
          for %{type: "VariableDeclarator", id: %{name: name}, init: init} <- decls,
              init != nil,
              %{type: "CallExpression", callee: %{name: "ref"}, arguments: args} <- [init],
              [arg | _] <- [args] do
            {name, slice_source(source, arg)}
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

  defp extract_computeds(ast, source) do
    OXC.collect(ast, fn
      %{type: "VariableDeclaration", declarations: decls} ->
        computeds =
          for %{type: "VariableDeclarator", id: %{name: name}, init: init} <- decls,
              init != nil,
              %{type: "CallExpression", callee: %{name: "computed"}, arguments: args} <- [init],
              [%{type: "ArrowFunctionExpression", body: body} | _] <- [args] do
            case body do
              %{type: "BlockStatement"} -> nil
              %{start: _, end: _} = expr_node -> {name, slice_source(source, expr_node)}
              _ -> nil
            end
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

  defp extract_function_bodies(ast, source) do
    OXC.collect(ast, fn
      %{type: "FunctionDeclaration", id: %{name: name}, body: %{start: s, end: e}} ->
        body = binary_part(source, s + 1, e - s - 2) |> String.trim()
        {:keep, {name, body}}

      _ ->
        :skip
    end)
    |> Map.new()
  end

  defp slice_source(source, %{start: s, end: e}) do
    binary_part(source, s, e - s)
  end

  defp slice_source(_source, _node), do: "null"
end
