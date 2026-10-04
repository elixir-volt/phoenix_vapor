defmodule PhoenixVapor.Expr do
  @moduledoc false

  @doc """
  Evaluate a Vapor IR expression against assigns.

  Handles:
  - Simple identifiers: `msg` → assigns.msg
  - Dot access: `user.name` → assigns.user.name
  - Array access: `items[0]` → assigns.items[0]
  - Ternary: `ok ? "yes" : "no"`
  - Logical: `a && b`, `a || b`
  - Unary: `!active`
  - Comparisons: `a === b`, `a !== b`, `a > b`, etc.
  - Arithmetic: `a + b`, `a - b`, `a * b`
  - Literals: strings, numbers, booleans, null
  - `.length` on lists

  Static literal values tagged as `{:static_, text}` are returned as-is.
  """
  @spec eval(String.t() | {:static_, String.t()} | compiled(), map()) :: term()
  def eval({:static_, text}, _assigns), do: text

  # A value computed at compile time, such as a folded macro call.
  def eval({:value, value}, _assigns), do: value

  # An expression only the browser can evaluate, reported when compiling.
  def eval({:unrendered, _source}, _assigns), do: nil

  # A macro call computed at compile time for each value its props can take,
  # looked up by their values.
  def eval({:lookup, source, keys, table}, assigns) do
    values = Enum.map(keys, &(assigns |> get_assign(&1) |> lookup_value()))

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

  def eval({:expr, source, nil, _keys}, assigns), do: resolve_path(source, assigns)

  def eval({:expr, source, node, _keys}, assigns) do
    eval_node(node, assigns)
  catch
    :unsupported_node -> quickbeam_eval(source, assigns)
  end

  def eval(expr, assigns) when is_binary(expr) do
    case parse_and_eval(expr, assigns) do
      {:ok, value} -> value
      :error -> resolve_path(expr, assigns)
      :fallback -> quickbeam_eval(expr, assigns)
    end
  end

  @typedoc "An expression parsed ahead of time by `compile/1`."
  @type compiled ::
          {:expr, String.t(), map() | nil, [String.t()]}
          | {:value, term()}
          | {:lookup, String.t(), [String.t()], %{[term()] => term()}}
          | {:unrendered, String.t()}

  @doc """
  Parses an expression once, for templates compiled into a module, so that
  rendering doesn't parse it again. `eval/2` and `assign_keys/1` accept the
  result in place of the source.
  """
  @spec compile(String.t() | {:static_, String.t()} | compiled()) ::
          compiled() | {:static_, String.t()}
  def compile({:static_, _} = static), do: static
  def compile({:value, _} = value), do: value
  def compile({:lookup, _, _, _} = lookup), do: lookup
  def compile({:unrendered, _} = unrendered), do: unrendered
  def compile({:expr, _, _, _} = compiled), do: compiled

  def compile(expr) when is_binary(expr) do
    case parse(expr) do
      nil -> {:expr, expr, nil, []}
      node -> {:expr, expr, node, free_names(node)}
    end
  end

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
  Evaluate a `values` list and concatenate results.
  """
  @spec eval_values([String.t() | {:static_, String.t()}], map()) :: String.t()
  def eval_values([single], assigns), do: to_string(eval(single, assigns))

  def eval_values(values, assigns) do
    values
    |> Enum.map(&(eval(&1, assigns) |> to_string()))
    |> IO.iodata_to_binary()
  end

  @doc """
  Extract root assign keys referenced by an expression.
  """
  @spec assign_keys(String.t() | {:static_, String.t()} | compiled()) :: [String.t()]
  def assign_keys({:static_, _}), do: []
  def assign_keys({:value, _}), do: []
  def assign_keys({:lookup, _source, keys, _table}), do: keys
  def assign_keys({:unrendered, _}), do: []
  def assign_keys({:expr, _source, _node, keys}), do: keys

  def assign_keys(expr) when is_binary(expr), do: free_names(expr)

  @doc """
  Extract root assign keys from a `values` list.
  """
  @spec values_assign_keys([String.t() | {:static_, String.t()}]) :: [String.t()]
  def values_assign_keys(values) do
    values
    |> Enum.flat_map(&assign_keys/1)
    |> Enum.uniq()
  end

  # Try to parse and evaluate using the OXC AST for complex expressions.
  # Falls back to simple path resolution for basic identifiers.
  defp parse_and_eval(expr, assigns) do
    case parse(expr) do
      nil ->
        :error

      node ->
        try do
          {:ok, eval_node(node, assigns)}
        catch
          :unsupported_node -> :fallback
        end
    end
  end

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
    |> Enum.map(fn {quasi, value} -> [quasi[:cooked] || quasi[:raw] || "", to_string(value)] end)
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
    if eval_node(test, assigns), do: eval_node(cons, assigns), else: eval_node(alt, assigns)
  end

  defp eval_node(%{type: :logical_expression, operator: op, left: left, right: right}, assigns) do
    case op do
      "&&" ->
        l = eval_node(left, assigns)
        if l, do: eval_node(right, assigns), else: l

      "||" ->
        l = eval_node(left, assigns)
        if l, do: l, else: eval_node(right, assigns)

      "??" ->
        l = eval_node(left, assigns)
        if l == nil, do: eval_node(right, assigns), else: l
    end
  end

  defp eval_node(%{type: :binary_expression, operator: op, left: left, right: right}, assigns) do
    l = eval_node(left, assigns)
    r = eval_node(right, assigns)

    case op do
      "+" -> numeric_or_string_add(l, r)
      "-" -> to_number(l) - to_number(r)
      "*" -> to_number(l) * to_number(r)
      "/" -> safe_div(to_number(l), to_number(r))
      "%" -> safe_rem(to_number(l), to_number(r))
      "===" -> l === r
      "!==" -> l !== r
      "==" -> l == r
      "!=" -> l != r
      ">" -> l > r
      ">=" -> l >= r
      "<" -> l < r
      "<=" -> l <= r
      _ -> nil
    end
  end

  defp eval_node(%{type: :unary_expression, operator: op, argument: arg}, assigns) do
    val = eval_node(arg, assigns)

    case op do
      "!" -> !val
      "-" -> -to_number(val)
      "+" -> to_number(val)
      "typeof" -> js_typeof(val)
      _ -> nil
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
          %{type: :literal, value: value} -> to_string(value)
          _ -> nil
        end

      if key do
        Map.put(acc, key, eval_node(prop.value, assigns))
      else
        acc
      end
    end)
  end

  defp eval_node(%{type: :call_expression, callee: callee, arguments: args}, assigns) do
    has_fn_args =
      Enum.any?(args || [], fn
        %{type: t} when t in [:arrow_function_expression, :function_expression] -> true
        _ -> false
      end)

    if has_fn_args do
      throw(:unsupported_node)
    end

    case callee do
      %{type: :member_expression, object: obj, property: %{name: method}} ->
        receiver = eval_node(obj, assigns)
        evaluated_args = Enum.map(args || [], &eval_node(&1, assigns))
        call_method(receiver, method, evaluated_args)

      # A call to a function: QuickBEAM runs it, or reports that it isn't one.
      _ ->
        throw(:unsupported_node)
    end
  end

  defp eval_node(%{type: type}, _assigns)
       when type in [
              :arrow_function_expression,
              :function_expression,
              :sequence_expression,
              :assignment_expression,
              :update_expression,
              :new_expression,
              :tagged_template_expression,
              :yield_expression,
              :await_expression
            ] do
    throw(:unsupported_node)
  end

  defp eval_node(_, _assigns), do: nil

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
        nil

      _ ->
        atom_key = String.to_existing_atom(name)
        Map.get(assigns, atom_key, Map.get(assigns, name))
    end
  rescue
    ArgumentError -> Map.get(assigns, name)
  end

  defp access_value(nil, _key), do: nil

  defp access_value(list, "length") when is_list(list), do: length(list)
  defp access_value(str, "length") when is_binary(str), do: String.length(str)

  defp access_value(map, key) when is_map(map) and is_binary(key) do
    case Map.get(map, key) do
      nil ->
        try do
          Map.get(map, String.to_existing_atom(key))
        rescue
          ArgumentError -> nil
        end

      val ->
        val
    end
  end

  defp access_value(list, index) when is_list(list) and is_integer(index) do
    Enum.at(list, index)
  end

  defp access_value(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end

  defp access_value(_, _), do: nil

  defp call_method(list, "join", [sep]) when is_list(list), do: Enum.join(list, to_string(sep))
  defp call_method(list, "join", []) when is_list(list), do: Enum.join(list, ",")
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
  defp call_method(_, _, _), do: throw(:unsupported_node)

  defp numeric_or_string_add(l, r) when is_binary(l) or is_binary(r),
    do: to_string(l) <> to_string(r)

  defp numeric_or_string_add(l, r), do: to_number(l) + to_number(r)

  defp to_number(n) when is_number(n), do: n
  defp to_number(true), do: 1
  defp to_number(false), do: 0
  defp to_number(nil), do: 0

  defp to_number(s) when is_binary(s) do
    case Float.parse(s) do
      {n, ""} -> n
      _ -> 0
    end
  end

  defp to_number(_), do: 0

  defp safe_div(_, 0), do: nil
  defp safe_div(_, +0.0), do: nil
  defp safe_div(a, b), do: a / b

  defp safe_rem(_, 0), do: nil
  defp safe_rem(_, +0.0), do: nil
  defp safe_rem(a, b) when is_integer(a) and is_integer(b), do: rem(a, b)
  defp safe_rem(a, b), do: :math.fmod(a, b)

  defp js_typeof(nil), do: "undefined"
  defp js_typeof(v) when is_boolean(v), do: "boolean"
  defp js_typeof(v) when is_number(v), do: "number"
  defp js_typeof(v) when is_binary(v), do: "string"
  defp js_typeof(v) when is_function(v), do: "function"
  defp js_typeof(_), do: "object"

  defp resolve_path(expr, assigns) do
    parts = String.split(expr, ".")

    Enum.reduce_while(parts, assigns, fn part, acc ->
      part = String.trim(part)

      if is_map(acc) do
        {:cont, Map.get(acc, part) || Map.get(acc, String.to_existing_atom(part))}
      else
        {:halt, nil}
      end
    end)
  rescue
    ArgumentError -> nil
  end

  # The globals a Vue template may use, from `GLOBALS_ALLOWED` in @vue/shared.
  @globals ~w(Infinity undefined NaN isFinite isNaN parseFloat parseInt decodeURI
              decodeURIComponent encodeURI encodeURIComponent Math Number Date Array
              Object Boolean String RegExp Map Set JSON Intl BigInt console Error Symbol)

  # Every other name the expression reads is defined, as `null` when it isn't
  # an assign, as Vue resolves an unknown name rather than throwing.
  defp quickbeam_eval(expr, assigns) do
    vars =
      expr
      |> free_names()
      |> Enum.reject(&(&1 in @globals))
      |> Map.new(&{&1, get_assign(assigns, &1)})

    case QuickBEAM.eval(quickbeam_runtime(), expr, vars: vars) do
      {:ok, result} ->
        result

      {:error, error} ->
        raise PhoenixVapor.ExpressionError, expression: expr, reason: Exception.message(error)
    end
  end

  @doc """
  The free names an expression reads: identifiers, but not property names
  such as `name` in `user.name` or `{ name: value }`.
  """
  @spec free_names(String.t() | map()) :: [String.t()]
  def free_names(expr) when is_binary(expr) do
    case OXC.parse(expr, "e.js") do
      {:ok, ast} -> free_names(ast)
      _ -> []
    end
  end

  def free_names(node), do: node |> collect_names([]) |> Enum.reverse() |> Enum.uniq()

  defp collect_names(%{type: :identifier, name: name}, acc), do: [name | acc]

  defp collect_names(%{type: :member_expression, object: object, property: property} = node, acc) do
    acc = collect_names(object, acc)
    if node[:computed], do: collect_names(property, acc), else: acc
  end

  defp collect_names(%{type: :property, key: key, value: value} = node, acc) do
    acc = if node[:computed], do: collect_names(key, acc), else: acc
    collect_names(value, acc)
  end

  defp collect_names(%{} = node, acc) do
    node
    |> Map.drop([:type, :start, :end])
    |> Enum.reduce(acc, fn {_key, value}, acc -> collect_names(value, acc) end)
  end

  defp collect_names(list, acc) when is_list(list), do: Enum.reduce(list, acc, &collect_names/2)
  defp collect_names(_value, acc), do: acc

  defp quickbeam_runtime do
    case Process.get(:phoenix_vapor_quickbeam_rt) do
      nil ->
        {:ok, rt} = QuickBEAM.start()
        Process.put(:phoenix_vapor_quickbeam_rt, rt)
        rt

      rt ->
        rt
    end
  end
end
