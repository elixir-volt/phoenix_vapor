defmodule PhoenixVapor.Template do
  @moduledoc """
  A Vue template compiled for rendering on the server: static HTML and the
  dynamic slots between it, the shape of `%Phoenix.LiveView.Rendered{}`.

  A template comes from `Vize.split_template/2`, compiled by PhoenixVapor's
  compiler. Its expressions are parsed, and every
  slot's `:position` is `{line, column}` in `:file`. Blocks inside it, such as
  a `v-if` branch, are templates too.
  """

  alias PhoenixVapor.Renderer.Expr

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

  @doc """
  Stores on every slot, in this template and the blocks inside it, the root
  assign keys its expressions read, its own and its blocks', as `:keys`.
  Rendering skips a slot none of whose keys changed. Call it again after
  replacing a template's expressions.
  """
  @spec put_keys(block) :: block when block: t() | map()
  def put_keys(%{slots: slots} = template) do
    slots =
      Enum.map(slots, fn slot ->
        {slot, nil} = map_blocks(slot, nil, &{put_keys(&1), &2})

        keys =
          (slot_exprs(slot) ++ slot_folded(slot))
          |> Enum.flat_map(&Expr.assign_keys/1)
          |> Enum.uniq()

        Map.put(slot, :keys, keys -- bound_names(slot))
      end)

    %{template | slots: slots}
  end

  # A `v-for` binds its item, key and index names inside its block; they
  # aren't assigns.
  defp bound_names(%{kind: :for} = slot),
    do: for(name <- [slot.value, slot[:key], slot[:index]], is_binary(name), do: name)

  defp bound_names(_slot), do: []

  @doc "Every expression in a template, in document order. See `map_exprs/3`."
  @spec exprs(t()) :: [{term(), map()}]
  def exprs(template) do
    {_template, exprs} =
      map_exprs(template, [], fn expr, slot, acc -> {expr, [{expr, slot} | acc]} end)

    Enum.reverse(exprs)
  end

  @doc """
  The prop expressions of the package components folded into a template, in
  it and the blocks inside it. Rendering doesn't evaluate them, but they
  decide the folded markup.
  """
  @spec folded(t() | map()) :: [term()]
  def folded(%{slots: slots}), do: Enum.flat_map(slots, &slot_folded/1)

  defp slot_folded(slot), do: Map.get(slot, :reads, []) ++ Enum.flat_map(blocks(slot), &folded/1)

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
  defp expr_fields(:model), do: [:value, :option_value]
  defp expr_fields(kind) when kind in [:text, :html, :spread], do: [:value]
  defp expr_fields(:attr), do: [:value, :name_value, :show]
  defp expr_fields(:for), do: [:source, :key_prop]
  defp expr_fields(:slot), do: [:name_value]
  defp expr_fields(:root_attrs), do: [:show]
  defp expr_fields(:fragments), do: [:inputs]
  defp expr_fields(_kind), do: []

  defp map_fields(slot, fields, acc, fun) do
    Enum.reduce(fields, {slot, acc}, fn field, {slot, acc} ->
      case slot do
        # A fragment per value of its inputs is looked up by all of them.
        %{^field => exprs} when is_list(exprs) ->
          {exprs, acc} = Enum.map_reduce(exprs, acc, &fun.(&1, slot, &2))
          {Map.put(slot, field, exprs), acc}

        %{^field => expr} when expr != nil ->
          {expr, acc} = fun.(expr, slot, acc)
          {Map.put(slot, field, expr), acc}

        _ ->
          {slot, acc}
      end
    end)
  end

  # Expressions held by what contains a slot's blocks, then the blocks.
  defp map_children(slot, acc, fun) do
    {slot, acc} = map_containers(slot, acc, at(fun, slot))
    map_blocks(slot, acc, &map_exprs(&1, &2, fun))
  end

  defp map_containers(%{kind: :if, branches: branches} = slot, acc, fun) do
    {branches, acc} = Enum.map_reduce(branches, acc, &map_fields(&1, [:condition], &2, fun))
    {%{slot | branches: branches}, acc}
  end

  defp map_containers(%{kind: :component} = slot, acc, fun) do
    {props, acc} = map_props(slot.props, acc, fun)
    {contents, acc} = Enum.map_reduce(slot.slots, acc, &map_fields(&1, [:name_value], &2, fun))
    {%{slot | props: props, slots: contents}, acc}
  end

  defp map_containers(%{kind: kind} = slot, acc, fun) when kind in [:slot, :root_attrs] do
    {props, acc} = map_props(slot.props, acc, fun)
    {%{slot | props: props}, acc}
  end

  defp map_containers(slot, acc, _fun), do: {slot, acc}

  @doc """
  Maps the blocks directly inside a slot, threading an accumulator: a
  `v-if`'s branches, a `v-for`'s body, a component's slot content, a
  `<slot>`'s fallback, a fragment's template, and the template for each
  value of a fragment's inputs, in the order of their values. Other slots
  have none.
  """
  @spec map_blocks(map(), acc, (block, acc -> {block, acc})) :: {map(), acc}
        when acc: term(), block: t() | map()
  def map_blocks(%{kind: :if, branches: branches} = slot, acc, fun) do
    {branches, acc} = Enum.map_reduce(branches, acc, &map_block(&1, :block, &2, fun))
    {%{slot | branches: branches}, acc}
  end

  def map_blocks(%{kind: :for} = slot, acc, fun), do: map_block(slot, :block, acc, fun)

  def map_blocks(%{kind: :component, slots: contents} = slot, acc, fun) do
    {contents, acc} = Enum.map_reduce(contents, acc, &map_block(&1, :block, &2, fun))
    {%{slot | slots: contents}, acc}
  end

  def map_blocks(%{kind: :slot, fallback: nil} = slot, acc, _fun), do: {slot, acc}
  def map_blocks(%{kind: :slot} = slot, acc, fun), do: map_block(slot, :fallback, acc, fun)
  def map_blocks(%{kind: :fragment} = slot, acc, fun), do: map_block(slot, :template, acc, fun)

  def map_blocks(%{kind: :fragments, table: table} = slot, acc, fun) do
    {table, acc} =
      table
      |> Enum.sort()
      |> Enum.map_reduce(acc, fn {values, block}, acc ->
        {block, acc} = fun.(block, acc)
        {{values, block}, acc}
      end)

    {%{slot | table: Map.new(table)}, acc}
  end

  def map_blocks(slot, acc, _fun), do: {slot, acc}

  defp map_block(container, field, acc, fun) do
    {block, acc} = fun.(Map.fetch!(container, field), acc)
    {Map.put(container, field, block), acc}
  end

  @doc "The blocks directly inside a slot. See `map_blocks/3`."
  @spec blocks(map()) :: [t() | map()]
  def blocks(slot) do
    {_slot, blocks} = map_blocks(slot, [], &{&1, [&1 | &2]})
    Enum.reverse(blocks)
  end

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
