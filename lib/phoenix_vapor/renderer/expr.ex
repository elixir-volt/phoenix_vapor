defmodule PhoenixVapor.Renderer.Expr do
  @moduledoc false

  alias PhoenixVapor.Renderer.Value

  @doc """
  Evaluates a compiled expression against assigns, with JavaScript's
  semantics (see `PhoenixVapor.Renderer.Value`). Identifiers, member access,
  literals, operators, conditionals, template literals, and common string and
  array methods evaluate in Elixir; anything else, such as a callback, runs in
  QuickBEAM.
  """
  @spec eval(compiled(), map()) :: term()

  # A value computed at compile time, such as a folded macro call.
  def eval({:value, value}, _assigns), do: value

  # An expression only the browser can evaluate, reported when compiling.
  def eval({:unrendered, _source}, _assigns), do: nil

  # A macro call computed at compile time for each value its props can take,
  # looked up by their values.
  def eval({:lookup, source, keys, table}, assigns) do
    values = Enum.map(keys, &(assigns |> get_assign(&1) |> Value.to_elixir() |> lookup_value()))

    case Map.fetch(table, values) do
      {:ok, value} ->
        value

      :error ->
        raise PhoenixVapor.ExpressionError,
          expression: source,
          reason:
            "#{Enum.map_join(Enum.zip(keys, values), ", ", fn {key, value} -> "#{key} is #{inspect(value)}" end)}, " <>
              "which its type doesn't allow"
    end
  end

  def eval({:expr, source, nil, _keys}, _assigns) do
    raise PhoenixVapor.ExpressionError,
      expression: source,
      reason: "it isn't a JavaScript expression"
  end

  # Only JavaScript can evaluate it, such as a call with a callback; the
  # compiler reports it.
  def eval({:js, _source, _node, _keys} = js, assigns), do: eval(js, assigns, [])

  # A method that isn't the value's, such as `trim()` on a number, throws in
  # the browser.
  def eval({:expr, source, node, _keys}, assigns) do
    node |> eval_node(assigns) |> Value.to_elixir()
  catch
    {:not_a_function, method} ->
      raise PhoenixVapor.ExpressionError,
        expression: source,
        reason: "`#{method}` isn't a function of that value"
  end

  @typedoc "An expression parsed ahead of time by `compile/1`."
  @type compiled ::
          {:expr | :js, String.t(), map() | nil, [String.t()]}
          | {:value, term()}
          | {:lookup, String.t(), [String.t()], %{[term()] => term()}}
          | {:unrendered, String.t()}

  @doc """
  Parses an expression once, when compiling a template, so that rendering
  doesn't parse it again. An expression Elixir evaluates is `{:expr, ...}`;
  one only JavaScript can, such as `items.filter(i => i.on)` or
  `Math.max(a, b)`, is `{:js, ...}` and runs in QuickBEAM when rendering.
  """
  @spec compile(String.t() | compiled()) :: compiled()
  def compile({:value, _} = value), do: value
  def compile({:lookup, _, _, _} = lookup), do: lookup
  def compile({:unrendered, _} = unrendered), do: unrendered
  def compile({tag, _, _, _} = compiled) when tag in [:expr, :js], do: compiled

  def compile(expr) when is_binary(expr) do
    case parse(expr) do
      nil -> {:expr, expr, nil, []}
      node -> from_node(expr, node)
    end
  end

  @doc "A compiled expression for `node`, parsed from `source` and possibly rewritten."
  @spec from_node(String.t(), map()) :: compiled()
  def from_node(source, node),
    do: {if(elixir?(node), do: :expr, else: :js), source, node, free_names(node)}

  # Vue parses an expression in parentheses, so `{ on: active }` is an object
  # rather than a block.
  defp parse(expr) do
    case OXC.parse("(" <> expr <> "\n)", "e.js") do
      {:ok, %{body: [%{type: :expression_statement, expression: node}]}} -> unwrap(node)
      _ -> nil
    end
  end

  defp unwrap(%{type: :parenthesized_expression, expression: node}), do: unwrap(node)
  defp unwrap(node), do: node

  @doc """
  Extract root assign keys referenced by an expression.
  """
  @spec assign_keys(compiled()) :: [String.t()]
  def assign_keys({:value, _}), do: []
  def assign_keys({:lookup, _source, keys, _table}), do: keys
  def assign_keys({:unrendered, _}), do: []
  def assign_keys({tag, _source, _node, keys}) when tag in [:expr, :js], do: keys

  # The globals a Vue template may use, from `GLOBALS_ALLOWED` in @vue/shared.
  @globals ~w(Infinity undefined NaN isFinite isNaN parseFloat parseInt decodeURI
              decodeURIComponent encodeURI encodeURIComponent Math Number Date Array
              Object Boolean String RegExp Map Set JSON Intl BigInt console Error Symbol)

  # The methods, operators and node types `eval_node/2` evaluates.
  @methods ~w(join includes trim toUpperCase toLowerCase startsWith endsWith)
  @binary ~w(+ - * / % === !== == != > >= < <=)
  @unary ~w(! - + typeof)
  @nodes [
    :parenthesized_expression,
    :identifier,
    :literal,
    :template_literal,
    :template_element,
    :member_expression,
    :conditional_expression,
    :logical_expression,
    :array_expression,
    :object_expression,
    :property
  ]

  @doc false
  # Whether Elixir evaluates the expression, rather than QuickBEAM.
  @spec elixir?(map()) :: boolean()
  def elixir?(%{type: :binary_expression, operator: op} = node),
    do: op in @binary and elixir?(node.left) and elixir?(node.right)

  def elixir?(%{type: :unary_expression, operator: op, argument: argument}),
    do: op in @unary and elixir?(argument)

  def elixir?(%{type: :property, computed: true}), do: false

  def elixir?(%{type: :call_expression, callee: callee, arguments: args}) do
    callable? =
      case callee do
        %{type: :member_expression, computed: false, object: object, property: %{name: method}} ->
          method in @methods and not global?(object) and elixir?(object)

        %{type: :identifier, name: name} ->
          name not in @globals

        %{type: :elixir_function} ->
          true

        _callee ->
          false
      end

    callable? and Enum.all?(args, &elixir?/1)
  end

  def elixir?(%{type: :member_expression, object: object, property: property} = node),
    do: not global?(object) and elixir?(object) and (not node[:computed] or elixir?(property))

  def elixir?(%{type: type} = node) when type in @nodes do
    Enum.all?(node, fn {key, value} -> key in [:type, :start, :end] or elixir?(value) end)
  end

  def elixir?(%{type: _type}), do: false
  def elixir?(list) when is_list(list), do: Enum.all?(list, &elixir?/1)
  def elixir?(_leaf), do: true

  defp global?(%{type: :identifier, name: name}), do: name in @globals
  defp global?(_node), do: false

  @doc "The globals a Vue template may use, which the server has too."
  @spec globals() :: [String.t()]
  def globals, do: @globals

  defp eval_node(%{type: :parenthesized_expression, expression: node}, assigns),
    do: eval_node(node, assigns)

  defp eval_node(%{type: :identifier, name: name}, assigns) do
    get_assign(assigns, name)
  end

  defp eval_node(%{type: :literal, value: value}, _assigns), do: value

  defp eval_node(%{type: :template_literal} = node, assigns) do
    quasis = node.quasis || []
    expressions = node.expressions || []

    # A template literal has one more quasi than it has expressions.
    values = Enum.map(expressions, &eval_node(&1, assigns)) ++ [""]

    quasis
    |> Enum.zip(values)
    |> Enum.map(fn {quasi, value} ->
      [quasi.value.cooked || quasi.value.raw, Value.to_js_string(value)]
    end)
    |> IO.iodata_to_binary()
  end

  defp eval_node(%{type: :member_expression, object: obj, property: prop} = node, assigns) do
    object_val = eval_node(obj, assigns)
    computed = Map.get(node, :computed, false)

    if computed do
      key = eval_node(prop, assigns)
      access_value(object_val, key)
    else
      key = prop.name
      access_value(object_val, key)
    end
  end

  defp eval_node(
         %{type: :conditional_expression, test: test, consequent: cons, alternate: alt},
         assigns
       ) do
    if Value.truthy?(eval_node(test, assigns)),
      do: eval_node(cons, assigns),
      else: eval_node(alt, assigns)
  end

  defp eval_node(%{type: :logical_expression, operator: op, left: left, right: right}, assigns) do
    case op do
      "&&" ->
        l = eval_node(left, assigns)
        if Value.truthy?(l), do: eval_node(right, assigns), else: l

      "||" ->
        l = eval_node(left, assigns)
        if Value.truthy?(l), do: l, else: eval_node(right, assigns)

      "??" ->
        l = eval_node(left, assigns)
        if l in [nil, :undefined], do: eval_node(right, assigns), else: l
    end
  end

  defp eval_node(%{type: :binary_expression, operator: op, left: left, right: right}, assigns) do
    l = eval_node(left, assigns)
    r = eval_node(right, assigns)

    case op do
      "+" -> Value.add(l, r)
      op when op in ["-", "*", "/", "%"] -> Value.arithmetic(op, l, r)
      "===" -> Value.strict_equal?(l, r)
      "!==" -> not Value.strict_equal?(l, r)
      "==" -> Value.loose_equal?(l, r)
      "!=" -> not Value.loose_equal?(l, r)
      op when op in [">", ">=", "<", "<="] -> Value.compare(op, l, r)
    end
  end

  defp eval_node(%{type: :unary_expression, operator: op, argument: arg}, assigns) do
    val = eval_node(arg, assigns)

    case op do
      "!" -> not Value.truthy?(val)
      "-" -> Value.negate(val)
      "+" -> Value.to_number(val)
      "typeof" -> Value.typeof(val)
    end
  end

  defp eval_node(%{type: :array_expression, elements: elements}, assigns) do
    Enum.map(elements || [], fn elem -> eval_node(elem, assigns) end)
  end

  defp eval_node(%{type: :object_expression, properties: properties}, assigns) do
    (properties || [])
    |> Enum.reduce(%{}, fn prop, acc ->
      key =
        case prop.key do
          %{type: :identifier, name: name} -> name
          %{type: :literal, value: value} -> Value.to_js_string(value)
          _ -> nil
        end

      if key do
        Map.put(acc, key, eval_node(prop.value, assigns))
      else
        acc
      end
    end)
  end

  # `elixir?/1` has checked the call is one evaluated here.
  defp eval_node(%{type: :call_expression, callee: callee, arguments: args}, assigns) do
    case callee do
      %{type: :member_expression, object: obj, property: %{name: method}} ->
        receiver = obj |> eval_node(assigns) |> Value.to_elixir()
        evaluated_args = Enum.map(args || [], &(&1 |> eval_node(assigns) |> Value.to_elixir()))
        call_method(receiver, method, evaluated_args)

      # A `<script setup>` function the SFC's `<script lang="elixir">` defines
      # for the server too.
      %{type: :elixir_function, module: module, function: function} ->
        apply(module, function, Enum.map(args, &(&1 |> eval_node(assigns) |> Value.to_elixir())))

      # A name that isn't a function here, as `undefined()` in the browser.
      %{type: :identifier, name: name} ->
        throw({:not_a_function, name})
    end
  end

  # Literal types are strings, numbers and booleans; an assign may hold an
  # atom for a string.
  defp lookup_value(value) when is_atom(value) and not is_boolean(value) and value != nil,
    do: Atom.to_string(value)

  defp lookup_value(value), do: value

  defp get_assign(assigns, name) do
    case name do
      "true" ->
        true

      "false" ->
        false

      "null" ->
        nil

      "undefined" ->
        :undefined

      "NaN" ->
        :nan

      "Infinity" ->
        :infinity

      _ ->
        fetch(assigns, name)
    end
  end

  # A key by its atom, if one exists, or its string; `undefined` if neither.
  defp fetch(map, name) do
    atom =
      try do
        String.to_existing_atom(name)
      rescue
        ArgumentError -> nil
      end

    case Map.fetch(map, atom) do
      {:ok, value} -> value
      :error -> Map.get(map, name, :undefined)
    end
  end

  # Reading a property of `null` or `undefined` throws in the browser, where
  # Vue renders nothing for the expression; here it's `undefined`.
  defp access_value(list, "length") when is_list(list), do: length(list)
  defp access_value(str, "length") when is_binary(str), do: String.length(str)

  defp access_value(map, key) when is_map(map) and not is_struct(map),
    do: fetch(map, Value.to_js_string(key))

  defp access_value(struct, key) when is_struct(struct),
    do: struct |> Map.from_struct() |> access_value(key)

  defp access_value(list, index) when is_list(list) do
    case Value.to_number(index) do
      index when is_integer(index) and index >= 0 -> list |> Enum.fetch(index) |> fetched()
      _other -> :undefined
    end
  end

  defp access_value(_value, _key), do: :undefined

  defp fetched({:ok, value}), do: value
  defp fetched(:error), do: :undefined

  defp call_method(list, "join", [sep]) when is_list(list),
    do: Enum.map_join(list, Value.to_js_string(sep), &join_item/1)

  defp call_method(list, "join", []) when is_list(list), do: Value.to_js_string(list)
  defp call_method(list, "includes", [val]) when is_list(list), do: val in list
  defp call_method(str, "trim", []) when is_binary(str), do: String.trim(str)
  defp call_method(str, "toUpperCase", []) when is_binary(str), do: String.upcase(str)
  defp call_method(str, "toLowerCase", []) when is_binary(str), do: String.downcase(str)

  defp call_method(str, "includes", [sub]) when is_binary(str),
    do: String.contains?(str, to_string(sub))

  defp call_method(str, "startsWith", [pre]) when is_binary(str),
    do: String.starts_with?(str, to_string(pre))

  defp call_method(str, "endsWith", [suf]) when is_binary(str),
    do: String.ends_with?(str, to_string(suf))

  # Anything else, such as filter/map with a callback, is evaluated in QuickBEAM.
  defp call_method(_value, method, _args), do: throw({:not_a_function, method})

  defp join_item(item) when item in [nil, :undefined], do: ""
  defp join_item(item), do: Value.to_js_string(item)

  # Every other name the expression reads is defined, as `null` when it isn't
  # an assign, as Vue resolves an unknown name rather than throwing.
  @doc """
  Like `eval/2`, with options for an expression only JavaScript evaluates:

    * `:runtime` — the QuickBEAM runtime to evaluate it in, such as a
      compile's; by default, the calling process's
  """
  @spec eval(compiled(), map(), keyword()) :: term()
  def eval({:js, source, _node, keys}, assigns, opts) do
    runtime = Keyword.get_lazy(opts, :runtime, &PhoenixVapor.JS.process_runtime/0)
    quickbeam_eval(source, keys, assigns, runtime)
  end

  def eval(compiled, assigns, _opts), do: eval(compiled, assigns)

  defp quickbeam_eval(expr, keys, assigns, runtime) do
    vars =
      keys
      |> Enum.reject(&(&1 in @globals))
      |> Map.new(&{&1, assigns |> get_assign(&1) |> Value.to_elixir()})

    case QuickBEAM.eval(runtime, expr, vars: vars) do
      {:ok, result} ->
        result

      {:error, error} ->
        raise PhoenixVapor.ExpressionError, expression: expr, reason: Exception.message(error)
    end
  end

  @doc """
  The free names an expression reads; see `PhoenixVapor.JS.FreeNames`.
  """
  @spec free_names(map()) :: [String.t()]
  def free_names(node), do: PhoenixVapor.JS.FreeNames.of(node)
end
