defmodule PhoenixVapor.JS.FreeNames do
  @moduledoc false

  # The free names a JavaScript AST from OXC reads: identifiers that aren't
  # bound inside it by a function's parameters, a declaration in an enclosing
  # block, or a `catch` clause. Property names, as in `a.b` or `{ b: 1 }`, and
  # labels aren't names.
  #
  # The walk is generic: only nodes that bind names or hold non-reference
  # identifiers are special, so a node type OXC adds is still walked.

  @doc """
  The free names `node` reads, in the order they first appear.

    * `:props` — report `props.x` as `"props.x"` rather than `"props"`, so a
      caller can tell which props an expression reads
  """
  @spec of(map() | [map()] | nil, keyword()) :: [String.t()]
  def of(node, opts \\ []) do
    node
    |> walk(MapSet.new(), Keyword.get(opts, :props, false), [])
    |> Enum.reverse()
    |> Enum.uniq()
  end

  defp walk(%{type: :identifier, name: name}, bound, _props?, acc),
    do: if(MapSet.member?(bound, name), do: acc, else: [name | acc])

  defp walk(
         %{
           type: :member_expression,
           object: %{type: :identifier, name: "props"},
           property: %{name: prop},
           computed: false
         },
         bound,
         true,
         acc
       ) do
    if MapSet.member?(bound, "props"), do: acc, else: ["props." <> prop | acc]
  end

  defp walk(
         %{type: :member_expression, object: object, property: property} = node,
         bound,
         props?,
         acc
       ) do
    acc = walk(object, bound, props?, acc)
    if node[:computed], do: walk(property, bound, props?, acc), else: acc
  end

  # An object literal's or class's key is a name only when computed.
  defp walk(%{type: type, key: key, value: value} = node, bound, props?, acc)
       when type in [:property, :method_definition, :property_definition] do
    acc = if node[:computed], do: walk(key, bound, props?, acc), else: acc
    walk(value, bound, props?, acc)
  end

  defp walk(%{type: type} = function, bound, props?, acc)
       when type in [:function_declaration, :function_expression, :arrow_function_expression] do
    own = if function[:id], do: [function.id.name], else: []
    params = function[:params] || []
    inner = bind(bound, own ++ Enum.flat_map(params, &pattern_names/1))

    # Defaults in parameters read the outer names, and earlier parameters.
    acc = Enum.reduce(params, acc, &pattern_defaults(&1, inner, props?, &2))
    walk(function.body, inner, props?, acc)
  end

  # A block's declarations are in scope throughout it.
  defp walk(%{type: type, body: body}, bound, props?, acc)
       when type in [:program, :block_statement, :function_body, :static_block] and
              is_list(body) do
    walk(body, bind(bound, Enum.flat_map(body, &declared_names/1)), props?, acc)
  end

  defp walk(%{type: type} = loop, bound, props?, acc)
       when type in [:for_statement, :for_in_statement, :for_of_statement] do
    head = loop[:init] || loop[:left]
    inner = bind(bound, declared_names(head))
    loop |> children() |> walk(inner, props?, acc)
  end

  defp walk(%{type: :catch_clause, param: param, body: body}, bound, props?, acc),
    do: walk(body, bind(bound, pattern_names(param)), props?, acc)

  defp walk(%{type: :variable_declarator, id: id, init: init}, bound, props?, acc) do
    acc = pattern_defaults(id, bound, props?, acc)
    walk(init, bound, props?, acc)
  end

  defp walk(%{type: :labeled_statement, body: body}, bound, props?, acc),
    do: walk(body, bound, props?, acc)

  defp walk(%{type: type}, _bound, _props?, acc)
       when type in [:break_statement, :continue_statement, :meta_property, :literal],
       do: acc

  defp walk(%{} = node, bound, props?, acc) do
    node |> children() |> walk(bound, props?, acc)
  end

  defp walk(list, bound, props?, acc) when is_list(list),
    do: Enum.reduce(list, acc, &walk(&1, bound, props?, &2))

  defp walk(_leaf, _bound, _props?, acc), do: acc

  # A node's children in source order, so names come out in the order they
  # appear.
  defp children(node) do
    node
    |> Map.drop([:type, :start, :end])
    |> Map.values()
    |> Enum.sort_by(&position/1)
  end

  defp position(%{start: start}), do: start
  defp position([first | _rest]), do: position(first)
  defp position(_leaf), do: 0

  defp bind(bound, names), do: Enum.reduce(names, bound, &MapSet.put(&2, &1))

  # The names a statement declares in its block.
  defp declared_names(%{type: :variable_declaration, declarations: declarations}),
    do: Enum.flat_map(declarations, &pattern_names(&1.id))

  defp declared_names(%{type: type, id: %{name: name}})
       when type in [:function_declaration, :class_declaration],
       do: [name]

  defp declared_names(_statement), do: []

  # The names a binding pattern binds.
  defp pattern_names(%{type: :identifier, name: name}), do: [name]
  defp pattern_names(%{type: :assignment_pattern, left: left}), do: pattern_names(left)
  defp pattern_names(%{type: :rest_element, argument: argument}), do: pattern_names(argument)
  defp pattern_names(%{type: :formal_parameter, pattern: pattern}), do: pattern_names(pattern)

  defp pattern_names(%{type: :array_pattern, elements: elements}),
    do: Enum.flat_map(elements || [], &pattern_names/1)

  defp pattern_names(%{type: :object_pattern, properties: properties}),
    do: Enum.flat_map(properties, &pattern_names(&1[:value] || &1[:argument] || &1))

  defp pattern_names(_node), do: []

  # What a pattern reads: default values and computed keys.
  defp pattern_defaults(
         %{type: :assignment_pattern, left: left, right: right},
         bound,
         props?,
         acc
       ),
       do: pattern_defaults(left, bound, props?, walk(right, bound, props?, acc))

  defp pattern_defaults(%{type: :formal_parameter, pattern: pattern}, bound, props?, acc),
    do: pattern_defaults(pattern, bound, props?, acc)

  defp pattern_defaults(%{type: :rest_element, argument: argument}, bound, props?, acc),
    do: pattern_defaults(argument, bound, props?, acc)

  defp pattern_defaults(%{type: :array_pattern, elements: elements}, bound, props?, acc),
    do: Enum.reduce(elements || [], acc, &pattern_defaults(&1, bound, props?, &2))

  defp pattern_defaults(%{type: :object_pattern, properties: properties}, bound, props?, acc) do
    Enum.reduce(properties, acc, fn property, acc ->
      acc = if property[:computed], do: walk(property.key, bound, props?, acc), else: acc
      pattern_defaults(property[:value] || property[:argument], bound, props?, acc)
    end)
  end

  defp pattern_defaults(_pattern, _bound, _props?, acc), do: acc
end
