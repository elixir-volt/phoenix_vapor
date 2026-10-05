defmodule PhoenixVapor.Renderer.Attrs do
  @moduledoc false

  # Renders a dynamic attribute the way Vue's server renderer does
  # (`ssrRenderDynamicAttr` in @vue/server-renderer): `null` leaves the
  # attribute out, a boolean attribute is present only when truthy, and
  # `class` and `style` accept Vue's object and array forms.

  alias PhoenixVapor.Renderer.Value

  # Vue's `isBooleanAttr`, from @vue/shared.
  @boolean_attrs ~w(itemscope allowfullscreen formnovalidate ismap nomodule novalidate readonly
                    async autofocus autoplay controls default defer disabled hidden inert loop open
                    required reversed scoped seamless checked muted multiple selected)

  @doc "Renders ` key=\"value\"`, ` key`, or nothing, with the leading space."
  @spec render(String.t(), [term()]) :: String.t()
  def render("class", values), do: attr("class", normalize_class(values))
  def render("style", values), do: attr("style", normalize_style(values))

  def render(key, [value]) when key in @boolean_attrs,
    do: if(Value.truthy?(value) or value == "", do: " " <> key, else: "")

  def render(_key, [value]) when not (is_binary(value) or is_number(value) or is_boolean(value)),
    do: ""

  def render(key, values) do
    case values |> Enum.map(&Value.to_js_string/1) |> IO.iodata_to_binary() do
      "" -> " " <> key
      value -> attr(key, value)
    end
  end

  defp attr(key, value), do: [?\s, key, ~s(="), escape(value), ?"] |> IO.iodata_to_binary()

  @doc "HTML-escapes text for an attribute value or text content."
  @spec escape(term()) :: String.t()
  def escape(value), do: value |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  @doc "Vue's `normalizeClass`: strings, arrays, and objects of class to condition."
  @spec normalize_class(term()) :: String.t()
  def normalize_class(value) when is_binary(value), do: value

  def normalize_class(values) when is_list(values) do
    values |> Enum.map(&normalize_class/1) |> Enum.reject(&(&1 == "")) |> Enum.join(" ")
  end

  def normalize_class(map) when is_map(map) do
    map
    |> Enum.filter(fn {_class, on} -> Value.truthy?(on) end)
    |> Enum.map_join(" ", &to_string(elem(&1, 0)))
  end

  def normalize_class(_value), do: ""

  @doc "Vue's `normalizeStyle` and `stringifyStyle`: strings, arrays, and objects of property to value."
  @spec normalize_style(term()) :: String.t()
  def normalize_style(value) when is_binary(value), do: value

  def normalize_style(values) when is_list(values) do
    values |> Enum.map(&normalize_style/1) |> Enum.reject(&(&1 == "")) |> Enum.join(";")
  end

  def normalize_style(map) when is_map(map) do
    Enum.map_join(map, fn
      {property, value} when is_binary(value) or is_number(value) ->
        "#{css_property(to_string(property))}:#{value};"

      _ignored ->
        ""
    end)
  end

  def normalize_style(_value), do: ""

  # Custom properties keep their case; others are hyphenated, as in Vue.
  defp css_property("--" <> _ = property), do: property

  defp css_property(property),
    do: Regex.replace(~r/\B([A-Z])/, property, "-\\1") |> String.downcase()
end
