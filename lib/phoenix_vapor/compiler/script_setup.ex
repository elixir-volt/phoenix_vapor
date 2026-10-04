defmodule PhoenixVapor.Compiler.ScriptSetup do
  @moduledoc false

  # Reads what `<script setup>` declares, from its OXC AST: `ref()` initial
  # expressions, `computed()` bodies, `defineProps`, and functions with their
  # bodies, for reactive and hybrid mode.

  @doc """
  Parse a `<script setup>` block and extract initial state + event handlers.

  Returns `{initial_assigns, computed_exprs, event_handlers}`.
  """
  def parse(script_source) do
    case OXC.parse(script_source, "setup.ts") do
      {:ok, ast} ->
        refs = extract_refs(ast, script_source)
        computeds = extract_computeds(ast, script_source)
        functions = extract_functions(ast)
        function_bodies = extract_function_bodies(ast, script_source)
        props = props(script_source)
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
    {:ok, rt} = QuickBEAM.start()

    try do
      Enum.reduce(refs, assigns, fn {name, init_expr}, acc ->
        case QuickBEAM.eval(rt, "(#{init_expr})") do
          {:ok, value} -> Map.put(acc, PhoenixVapor.Renderer.Names.atom!(name), value)
          _ -> Map.put(acc, PhoenixVapor.Renderer.Names.atom!(name), nil)
        end
      end)
    after
      QuickBEAM.stop(rt)
    end
  end

  defp extract_refs(ast, source) do
    OXC.collect(ast, fn
      %{type: :variable_declaration, declarations: decls} ->
        refs =
          for %{type: :variable_declarator, id: %{name: name}, init: init} <- decls,
              init != nil,
              %{type: :call_expression, callee: %{name: "ref"}, arguments: args} <- [init],
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
      %{type: :variable_declaration, declarations: decls} ->
        computeds =
          for %{type: :variable_declarator, id: %{name: name}, init: init} <- decls,
              init != nil,
              %{type: :call_expression, callee: %{name: "computed"}, arguments: args} <- [init],
              [%{type: :arrow_function_expression, body: body} | _] <- [args] do
            case body do
              %{type: :block_statement, start: _, end: _} = block ->
                {name, slice_source(source, block)}

              %{start: _, end: _} = expr_node ->
                {name, slice_source(source, expr_node)}

              _ ->
                nil
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
      %{type: :function_declaration, id: %{name: name}} ->
        {:keep, name}

      _ ->
        :skip
    end)
  end

  # Vize's analysis reads every defineProps form: array, object, and
  # TypeScript type arguments.
  defp props(script_source) do
    case Vize.analyze_sfc(~s(<script setup lang="ts">\n) <> script_source <> "\n</script>") do
      {:ok, croquis} -> Enum.map(croquis.props, & &1.name)
      {:error, _} -> []
    end
  end

  defp extract_function_bodies(ast, source) do
    OXC.collect(ast, fn
      %{type: :function_declaration, id: %{name: name}, body: %{start: s, end: e}} ->
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
