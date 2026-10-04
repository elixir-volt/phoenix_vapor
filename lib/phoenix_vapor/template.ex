defmodule PhoenixVapor.Template do
  @moduledoc """
  A Vue template compiled for rendering on the server: static HTML and the
  dynamic slots between it, the shape of `%Phoenix.LiveView.Rendered{}`.

  A template comes from `Vize.split_template/2` through
  `PhoenixVapor.Compiler.Split.compile/2`. Its expressions are parsed, and every
  slot's `:position` is `{line, column}` in `:file`. Blocks inside it, such as
  a `v-if` branch, are templates too.
  """

  defstruct statics: [], slots: [], fingerprint: nil, file: nil

  @type position :: {pos_integer(), pos_integer()}

  @type t :: %__MODULE__{
          statics: [String.t()],
          slots: [map()],
          fingerprint: non_neg_integer() | nil,
          file: Path.t() | nil
        }

  @doc """
  A template from its statics and compiled slots, with their fingerprint.
  """
  @spec new([String.t()], [map()], Path.t() | nil) :: t()
  def new(statics, slots, file) do
    %__MODULE__{
      statics: statics,
      slots: slots,
      fingerprint: fingerprint(statics, slots),
      file: file
    }
  end

  @doc """
  Identifies statics and slots, as the fingerprint of a
  `%Phoenix.LiveView.Rendered{}` does, so LiveView sends statics only when
  they change.
  """
  @spec fingerprint([String.t()], [map()]) :: non_neg_integer()
  def fingerprint(statics, slots) do
    <<fingerprint::8*16>> = [statics | slots] |> :erlang.term_to_binary() |> :erlang.md5()
    fingerprint
  end

  @doc """
  Maps every expression in a template, threading an accumulator: `fun` gets
  the expression, the slot it belongs to, and the accumulator. A component's
  own template, under `:component`, belongs to that component and is skipped.
  """
  @spec map_exprs(block, acc, (term(), map(), acc -> {term(), acc})) :: {block, acc}
        when block: t() | %{slots: [map()]}, acc: term()
  def map_exprs(%{slots: slots} = template, acc, fun) do
    {slots, acc} = Enum.map_reduce(slots, acc, &map_slot(&1, &2, fun))
    {%{template | slots: slots}, acc}
  end

  @doc "Every expression in a template, in document order. See `map_exprs/3`."
  @spec exprs(t()) :: [{term(), map()}]
  def exprs(template) do
    {_template, exprs} =
      map_exprs(template, [], fn expr, slot, acc -> {expr, [{expr, slot} | acc]} end)

    Enum.reverse(exprs)
  end

  @doc "The expressions in one slot, including the blocks inside it."
  @spec slot_exprs(map()) :: [term()]
  def slot_exprs(slot) do
    {_slot, exprs} = map_slot(slot, [], fn expr, _slot, acc -> {expr, [expr | acc]} end)
    Enum.reverse(exprs)
  end

  defp map_slot(slot, acc, fun) do
    {slot, acc} = map_fields(slot, expr_fields(slot.kind), acc, fun)
    map_children(slot, acc, fun)
  end

  # The fields of each slot kind that hold expressions. A `v-for`'s `:value`
  # and `:key` are the names it binds, not expressions.
  defp expr_fields(kind) when kind in [:text, :html, :spread, :model], do: [:value]
  defp expr_fields(:attr), do: [:value, :name_value, :show]
  defp expr_fields(:for), do: [:source, :key_prop]
  defp expr_fields(:slot), do: [:name_value]
  defp expr_fields(:root_attrs), do: [:show]
  defp expr_fields(_kind), do: []

  defp map_fields(slot, fields, acc, fun) do
    Enum.reduce(fields, {slot, acc}, fn field, {slot, acc} ->
      case slot do
        %{^field => expr} when expr != nil ->
          {expr, acc} = fun.(expr, slot, acc)
          {Map.put(slot, field, expr), acc}

        _ ->
          {slot, acc}
      end
    end)
  end

  defp map_children(%{kind: :if, branches: branches} = slot, acc, fun) do
    {branches, acc} =
      Enum.map_reduce(branches, acc, fn branch, acc ->
        {branch, acc} = map_fields(branch, [:condition], acc, at(fun, slot))
        {block, acc} = map_exprs(branch.block, acc, fun)
        {%{branch | block: block}, acc}
      end)

    {%{slot | branches: branches}, acc}
  end

  defp map_children(%{kind: :for, block: block} = slot, acc, fun) do
    {block, acc} = map_exprs(block, acc, fun)
    {%{slot | block: block}, acc}
  end

  defp map_children(%{kind: :component} = slot, acc, fun) do
    {props, acc} = map_props(slot.props, acc, at(fun, slot))

    {contents, acc} =
      Enum.map_reduce(slot.slots, acc, fn content, acc ->
        {content, acc} = map_fields(content, [:name_value], acc, at(fun, slot))
        {block, acc} = map_exprs(content.block, acc, fun)
        {%{content | block: block}, acc}
      end)

    {%{slot | props: props, slots: contents}, acc}
  end

  defp map_children(%{kind: :slot} = slot, acc, fun) do
    {props, acc} = map_props(slot.props, acc, at(fun, slot))

    {fallback, acc} =
      case slot.fallback do
        nil -> {nil, acc}
        block -> map_exprs(block, acc, fun)
      end

    {%{slot | props: props, fallback: fallback}, acc}
  end

  defp map_children(%{kind: :fragment, template: template} = slot, acc, fun) do
    {template, acc} = map_exprs(template, acc, fun)
    {%{slot | template: template}, acc}
  end

  defp map_children(%{kind: :root_attrs} = slot, acc, fun) do
    {props, acc} = map_props(slot.props, acc, at(fun, slot))
    {%{slot | props: props}, acc}
  end

  defp map_children(slot, acc, _fun), do: {slot, acc}

  # Expressions in a slot's props, branches, and slot contents are reported
  # with the slot, which has their position.
  defp at(fun, slot), do: fn expr, _owner, acc -> fun.(expr, slot, acc) end

  defp map_props(props, acc, fun),
    do: Enum.map_reduce(props, acc, &map_fields(&1, [:value, :name_value], &2, fun))

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(%{file: file, slots: slots}, opts) do
      location = if file, do: Path.relative_to_cwd(file) <> ", ", else: ""
      count = length(slots)

      concat([
        "#PhoenixVapor.Template<",
        location,
        to_doc(count, opts),
        if(count == 1, do: " slot>", else: " slots>")
      ])
    end
  end
end
