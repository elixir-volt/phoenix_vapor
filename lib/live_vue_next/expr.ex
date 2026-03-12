defmodule LiveVueNext.Expr do
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
  @spec eval(String.t() | {:static_, String.t()}, map()) :: term()
  def eval({:static_, text}, _assigns), do: text

  def eval(expr, assigns) when is_binary(expr) do
    case parse_and_eval(expr, assigns) do
      {:ok, value} -> value
      :error -> resolve_path(expr, assigns)
      :fallback -> LiveVueNext.JsEval.eval(expr, assigns)
    end
  end

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
  @spec assign_keys(String.t() | {:static_, String.t()}) :: [atom()]
  def assign_keys({:static_, _}), do: []

  def assign_keys(expr) when is_binary(expr) do
    case OXC.parse(expr, "e.js") do
      {:ok, ast} ->
        OXC.collect(ast, fn
          %{type: "Identifier", name: name} -> {:keep, String.to_atom(name)}
          _ -> :skip
        end)
        |> Enum.uniq()

      _ ->
        root = expr |> String.split(".") |> hd() |> String.trim()
        if root == "", do: [], else: [String.to_atom(root)]
    end
  end

  @doc """
  Extract root assign keys from a `values` list.
  """
  @spec values_assign_keys([String.t() | {:static_, String.t()}]) :: [atom()]
  def values_assign_keys(values) do
    values
    |> Enum.flat_map(&assign_keys/1)
    |> Enum.uniq()
  end

  # Try to parse and evaluate using the OXC AST for complex expressions.
  # Falls back to simple path resolution for basic identifiers.
  defp parse_and_eval(expr, assigns) do
    case OXC.parse(expr, "e.js") do
      {:ok, %{body: [%{type: "ExpressionStatement", expression: node}]}} ->
        try do
          {:ok, eval_node(node, assigns)}
        catch
          :unsupported_node -> :fallback
        end

      _ ->
        :error
    end
  end

  defp eval_node(%{type: "Identifier", name: name}, assigns) do
    get_assign(assigns, name)
  end

  defp eval_node(%{type: "Literal", value: value}, _assigns), do: value

  defp eval_node(%{type: "TemplateLiteral"} = node, assigns) do
    quasis = node.quasis || []
    expressions = node.expressions || []

    parts =
      Enum.with_index(quasis)
      |> Enum.flat_map(fn {quasi, i} ->
        cooked = quasi[:cooked] || quasi[:raw] || ""
        expr_val = if i < length(expressions), do: [eval_node(Enum.at(expressions, i), assigns)], else: []
        [cooked | expr_val]
      end)

    parts |> Enum.map(&to_string/1) |> IO.iodata_to_binary()
  end

  defp eval_node(%{type: "MemberExpression", object: obj, property: prop} = node, assigns) do
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

  defp eval_node(%{type: "ConditionalExpression", test: test, consequent: cons, alternate: alt}, assigns) do
    if eval_node(test, assigns), do: eval_node(cons, assigns), else: eval_node(alt, assigns)
  end

  defp eval_node(%{type: "LogicalExpression", operator: op, left: left, right: right}, assigns) do
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

  defp eval_node(%{type: "BinaryExpression", operator: op, left: left, right: right}, assigns) do
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

  defp eval_node(%{type: "UnaryExpression", operator: op, argument: arg}, assigns) do
    val = eval_node(arg, assigns)

    case op do
      "!" -> !val
      "-" -> -to_number(val)
      "+" -> to_number(val)
      "typeof" -> js_typeof(val)
      _ -> nil
    end
  end

  defp eval_node(%{type: "ArrayExpression", elements: elements}, assigns) do
    Enum.map(elements || [], fn elem -> eval_node(elem, assigns) end)
  end

  defp eval_node(%{type: "ObjectExpression", properties: properties}, assigns) do
    (properties || [])
    |> Enum.reduce(%{}, fn prop, acc ->
      key =
        case prop.key do
          %{type: "Identifier", name: name} -> name
          %{type: "Literal", value: value} -> to_string(value)
          _ -> nil
        end

      if key do
        Map.put(acc, key, eval_node(prop.value, assigns))
      else
        acc
      end
    end)
  end

  defp eval_node(%{type: "CallExpression", callee: callee, arguments: args}, assigns) do
    has_fn_args =
      Enum.any?(args || [], fn
        %{type: t} when t in ["ArrowFunctionExpression", "FunctionExpression"] -> true
        _ -> false
      end)

    if has_fn_args do
      throw(:unsupported_node)
    end

    case callee do
      %{type: "MemberExpression", object: obj, property: %{name: method}} ->
        receiver = eval_node(obj, assigns)
        evaluated_args = Enum.map(args || [], &eval_node(&1, assigns))
        call_method(receiver, method, evaluated_args)

      _ ->
        nil
    end
  end

  defp eval_node(%{type: type}, _assigns)
       when type in ["ArrowFunctionExpression", "FunctionExpression", "SequenceExpression",
                      "AssignmentExpression", "UpdateExpression", "NewExpression",
                      "TaggedTemplateExpression", "YieldExpression", "AwaitExpression"] do
    throw(:unsupported_node)
  end

  defp eval_node(_, _assigns), do: nil

  defp get_assign(assigns, name) do
    case name do
      "true" -> true
      "false" -> false
      "null" -> nil
      "undefined" -> nil
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

  defp call_method(list, "filter", [_fun]) when is_list(list), do: list
  defp call_method(list, "map", [_fun]) when is_list(list), do: list
  defp call_method(list, "join", [sep]) when is_list(list), do: Enum.join(list, to_string(sep))
  defp call_method(list, "join", []) when is_list(list), do: Enum.join(list, ",")
  defp call_method(list, "includes", [val]) when is_list(list), do: val in list
  defp call_method(str, "trim", []) when is_binary(str), do: String.trim(str)
  defp call_method(str, "toUpperCase", []) when is_binary(str), do: String.upcase(str)
  defp call_method(str, "toLowerCase", []) when is_binary(str), do: String.downcase(str)
  defp call_method(str, "includes", [sub]) when is_binary(str), do: String.contains?(str, to_string(sub))
  defp call_method(str, "startsWith", [pre]) when is_binary(str), do: String.starts_with?(str, to_string(pre))
  defp call_method(str, "endsWith", [suf]) when is_binary(str), do: String.ends_with?(str, to_string(suf))
  defp call_method(_, _, _), do: nil

  defp numeric_or_string_add(l, r) when is_binary(l) or is_binary(r), do: to_string(l) <> to_string(r)
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

      cond do
        is_map(acc) ->
          value = Map.get(acc, part) || Map.get(acc, String.to_existing_atom(part))
          {:cont, value}

        true ->
          {:halt, nil}
      end
    end)
  rescue
    ArgumentError -> nil
  end
end
