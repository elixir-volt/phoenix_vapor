defmodule PhoenixVapor.Renderer.Value do
  @moduledoc false

  # JavaScript's value semantics for template expressions, so a template
  # renders on the server as Vue renders it in the browser: ToBoolean,
  # ToNumber, String(), Vue's `toDisplayString`, `===`, `==`, relational
  # comparison, `+`, and `typeof`.
  #
  # Elixir values stand for JavaScript ones: `nil` is `null`, as JSON makes it
  # when the server passes props to the browser, and lists and maps are arrays
  # and objects. While an expression evaluates, a missing assign or property
  # is `:undefined`, and arithmetic can produce `:nan`, `:infinity` and
  # `:neg_infinity`.

  @type t :: term()

  @special [:undefined, :nan, :infinity, :neg_infinity]

  @doc "JavaScript's ToBoolean."
  @spec truthy?(t()) :: boolean()
  def truthy?(value) when value in [false, nil, :undefined, :nan, ""], do: false
  def truthy?(value) when is_number(value), do: value != 0
  def truthy?(_value), do: true

  @doc "JavaScript's ToNumber."
  @spec to_number(t()) :: number() | :nan | :infinity | :neg_infinity
  def to_number(value) when is_number(value), do: value
  def to_number(value) when value in [:nan, :infinity, :neg_infinity], do: value
  def to_number(nil), do: 0
  def to_number(true), do: 1
  def to_number(false), do: 0
  def to_number([]), do: 0
  def to_number([single]), do: to_number(single)

  def to_number(text) when is_binary(text) do
    case String.trim(text) do
      "" ->
        0

      "Infinity" ->
        :infinity

      "-Infinity" ->
        :neg_infinity

      trimmed ->
        case Integer.parse(trimmed) do
          {integer, ""} ->
            integer

          _other ->
            case Float.parse(trimmed) do
              {float, ""} -> float
              _other -> :nan
            end
        end
    end
  end

  def to_number(_value), do: :nan

  @doc "JavaScript's `String(value)`, as `+` and template literals convert."
  @spec to_js_string(t()) :: String.t()
  def to_js_string(nil), do: "null"
  def to_js_string(:undefined), do: "undefined"
  def to_js_string(:nan), do: "NaN"
  def to_js_string(:infinity), do: "Infinity"
  def to_js_string(:neg_infinity), do: "-Infinity"
  def to_js_string(value) when is_binary(value), do: value
  def to_js_string(value) when is_boolean(value), do: Atom.to_string(value)
  def to_js_string(value) when is_integer(value), do: Integer.to_string(value)

  def to_js_string(value) when is_float(value) do
    whole = trunc(value)
    if whole == value, do: Integer.to_string(whole), else: Float.to_string(value)
  end

  def to_js_string(list) when is_list(list),
    do: Enum.map_join(list, ",", &if(&1 in [nil, :undefined], do: "", else: to_js_string(&1)))

  def to_js_string(map) when is_map(map), do: "[object Object]"
  def to_js_string(atom) when is_atom(atom), do: Atom.to_string(atom)

  @doc "Vue's `toDisplayString`, for `{{ }}`."
  @spec display(t()) :: String.t()
  def display(value) when value in [nil, :undefined], do: ""

  def display(value) when (is_map(value) and not is_struct(value)) or is_list(value),
    do: Jason.encode!(value, pretty: true)

  def display(value), do: to_js_string(value)

  @doc "`===`. Lists and maps compare by contents, having no identity here."
  @spec strict_equal?(t(), t()) :: boolean()
  def strict_equal?(:nan, _right), do: false
  def strict_equal?(_left, :nan), do: false
  def strict_equal?(left, right) when is_number(left) and is_number(right), do: left == right
  def strict_equal?(left, right), do: left === right

  @doc "`==`: `null` equals `undefined`, and numbers compare with what converts to one."
  @spec loose_equal?(t(), t()) :: boolean()
  def loose_equal?(left, right) when left in [nil, :undefined] and right in [nil, :undefined],
    do: true

  def loose_equal?(left, right) when left in [nil, :undefined] or right in [nil, :undefined],
    do: false

  def loose_equal?(left, right) when is_boolean(left), do: loose_equal?(to_number(left), right)
  def loose_equal?(left, right) when is_boolean(right), do: loose_equal?(left, to_number(right))

  def loose_equal?(left, right)
      when (is_number(left) and is_binary(right)) or (is_binary(left) and is_number(right)),
      do: strict_equal?(to_number(left), to_number(right))

  def loose_equal?(left, right), do: strict_equal?(left, right)

  @doc "`<`, `<=`, `>` and `>=`: strings compare as strings, anything else as numbers."
  @spec compare(String.t(), t(), t()) :: boolean()
  def compare(operator, left, right) when is_binary(left) and is_binary(right),
    do: apply_operator(operator, left, right)

  def compare(operator, left, right) do
    case {rank(to_number(left)), rank(to_number(right))} do
      {:nan, _right} -> false
      {_left, :nan} -> false
      {left, right} -> apply_operator(operator, left, right)
    end
  end

  # Infinities order around every number.
  defp rank(:nan), do: :nan
  defp rank(:infinity), do: {2, 0}
  defp rank(:neg_infinity), do: {0, 0}
  defp rank(number), do: {1, number}

  defp apply_operator("<", left, right), do: left < right
  defp apply_operator("<=", left, right), do: left <= right
  defp apply_operator(">", left, right), do: left > right
  defp apply_operator(">=", left, right), do: left >= right

  @doc "`+`: concatenation when either side converts to a string, otherwise addition."
  @spec add(t(), t()) :: t()
  def add(left, right)
      when is_binary(left) or is_binary(right) or is_list(left) or is_list(right) or
             (is_map(left) and not is_struct(left)) or (is_map(right) and not is_struct(right)),
      do: to_js_string(left) <> to_js_string(right)

  def add(left, right), do: compute("+", to_number(left), to_number(right))

  @doc "`-`, `*`, `/` and `%` on numbers, with JavaScript's NaN and Infinity."
  @spec arithmetic(String.t(), t(), t()) :: number() | :nan | :infinity | :neg_infinity
  def arithmetic(operator, left, right), do: compute(operator, to_number(left), to_number(right))

  defp compute(_operator, :nan, _right), do: :nan
  defp compute(_operator, _left, :nan), do: :nan

  defp compute(operator, left, right) when left in @special or right in @special,
    do: infinite(operator, left, right)

  defp compute("+", left, right), do: left + right
  defp compute("-", left, right), do: left - right
  defp compute("*", left, right), do: left * right

  defp compute("/", left, right) when right in [0, +0.0, -0.0] do
    cond do
      left == 0 -> :nan
      left > 0 -> :infinity
      true -> :neg_infinity
    end
  end

  defp compute("/", left, right), do: left / right
  defp compute("%", _left, right) when right in [0, +0.0, -0.0], do: :nan
  defp compute("%", left, right) when is_integer(left) and is_integer(right), do: rem(left, right)
  defp compute("%", left, right), do: :math.fmod(left, right)

  # Arithmetic where at least one side is infinite.
  defp infinite("+", left, right) do
    case {sign(left), sign(right)} do
      {2, -2} -> :nan
      {-2, 2} -> :nan
      {l, _r} when abs(l) == 2 -> left
      _right_infinite -> right
    end
  end

  defp infinite("-", left, right), do: infinite("+", left, negate(right))

  defp infinite("*", left, right) do
    case sign(left) * sign(right) do
      0 -> :nan
      product -> infinity(product)
    end
  end

  defp infinite("/", left, right) do
    case {abs(sign(left)), abs(sign(right))} do
      {2, 2} -> :nan
      {2, _finite} -> infinity(sign(left) * if(sign(right) < 0, do: -1, else: 1))
      {_finite, 2} -> 0
    end
  end

  defp infinite("%", left, _right), do: if(abs(sign(left)) == 2, do: :nan, else: left)

  # -2 and 2 for the infinities; -1, 0 and 1 for numbers.
  defp sign(:infinity), do: 2
  defp sign(:neg_infinity), do: -2
  defp sign(number) when number > 0, do: 1
  defp sign(number) when number < 0, do: -1
  defp sign(_zero), do: 0

  defp infinity(sign) when sign > 0, do: :infinity
  defp infinity(_sign), do: :neg_infinity

  @doc "Unary `-`."
  @spec negate(t()) :: t()
  def negate(value) do
    case to_number(value) do
      :nan -> :nan
      :infinity -> :neg_infinity
      :neg_infinity -> :infinity
      number -> -number
    end
  end

  @doc "`typeof`."
  @spec typeof(t()) :: String.t()
  def typeof(:undefined), do: "undefined"
  def typeof(value) when value in [:nan, :infinity, :neg_infinity], do: "number"
  def typeof(value) when is_boolean(value), do: "boolean"
  def typeof(value) when is_number(value), do: "number"
  def typeof(value) when is_binary(value), do: "string"
  def typeof(value) when is_function(value), do: "function"
  def typeof(_value), do: "object"

  @doc """
  The value as Elixir sees it outside an expression: `undefined` is `nil`.
  NaN and the infinities stay atoms, which display as JavaScript prints them.
  """
  @spec to_elixir(t()) :: term()
  def to_elixir(:undefined), do: nil
  def to_elixir(value), do: value
end
