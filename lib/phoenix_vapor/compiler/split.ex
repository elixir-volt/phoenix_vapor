defmodule PhoenixVapor.Compiler.Split do
  @moduledoc false

  # Compiles `Vize.split_template/2` output into a `PhoenixVapor.Template`.

  alias PhoenixVapor.Renderer.Expr
  alias PhoenixVapor.Template

  @doc """
  Compiles a split: parses every expression, renders its bindings, positions
  its slots in `:file`, and computes each block's fingerprint.

  Vize leaves events and `v-model` unrendered and reports where each element's
  start tag ends. LiveView handles them through `phx-*` attributes; pass
  `events: false` when client code handles the template's events instead.

  ## Options

    * `:events` — render events as `phx-*` attributes (default: `true`)
    * `:file` — the file the template is in
    * `:origin` — `{line, column}` where the template starts in `:file`
  """
  @spec compile(map(), keyword()) :: Template.t()
  def compile(%{statics: statics, slots: slots} = split, opts \\ []) do
    statics = render_bindings(statics, Map.get(split, :bindings, []), opts)
    slots = Enum.map(slots, &compile_slot(&1, opts))

    Template.new(statics, slots, opts[:file])
  end

  defp render_bindings(statics, bindings, opts) do
    events? = Keyword.get(opts, :events, true)

    inserts =
      bindings
      |> Enum.flat_map(fn %{at: {index, offset}} = binding ->
        case binding_attribute(binding, events?) do
          nil -> []
          attribute -> [{index, offset, attribute}]
        end
      end)
      |> Enum.group_by(&elem(&1, 0), &Tuple.delete_at(&1, 0))

    statics
    |> Enum.with_index()
    |> Enum.map(fn {static, index} -> splice(static, Map.get(inserts, index, [])) end)
  end

  defp splice(static, []), do: static

  # Inserts attributes at byte offsets. The sort is stable, so attributes at
  # the same offset keep their order.
  defp splice(static, inserts) do
    {parts, position} =
      inserts
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map_reduce(0, fn {offset, attribute}, position ->
        {[binary_part(static, position, offset - position), attribute], offset}
      end)

    IO.iodata_to_binary([parts, binary_part(static, position, byte_size(static) - position)])
  end

  defp binding_attribute(_binding, false), do: nil
  defp binding_attribute(%{kind: :on, name: nil}, true), do: nil

  defp binding_attribute(%{kind: :on, name: event, value: value}, true),
    do: ~s( phx-#{event}="#{Phoenix.HTML.Engine.html_escape(value || event)}")

  defp binding_attribute(%{kind: :model, value: value}, true),
    do: ~s( phx-change="#{Phoenix.HTML.Engine.html_escape(value <> "_changed")}")

  # Blocks inside the slot compile first; compiling an expression twice
  # returns it as it is.
  defp compile_slot(slot, opts) do
    slot
    |> compile_blocks(opts)
    |> compile_exprs()
    |> Map.update(:position, nil, &position(&1, opts))
  end

  defp compile_exprs(slot) do
    {%{slots: [slot]}, nil} =
      Template.map_exprs(%{slots: [slot]}, nil, fn expr, _slot, acc ->
        {Expr.compile(expr), acc}
      end)

    slot
  end

  defp compile_blocks(%{kind: :if, branches: branches} = slot, opts),
    do: %{slot | branches: Enum.map(branches, &%{&1 | block: compile(&1.block, opts)})}

  defp compile_blocks(%{kind: :for, block: block} = slot, opts),
    do: %{slot | block: compile(block, opts)}

  defp compile_blocks(%{kind: :component, slots: contents} = slot, opts) do
    contents =
      for content <- contents do
        %{content | block: compile(content.block, opts)}
        |> Map.put(:params, slot_params(content.params))
      end

    %{slot | slots: contents}
  end

  defp compile_blocks(%{kind: :slot, fallback: fallback} = slot, opts),
    do: %{slot | fallback: fallback && compile(fallback, opts)}

  defp compile_blocks(slot, _opts), do: slot

  defp position({line, column}, opts),
    do: Vize.Diagnostic.shift({line, column}, Keyword.get(opts, :origin, {1, 1}))

  # How slot content binds the props its outlet passes: `#item="{ id, name: label }"`
  # binds `id` and `label`, and `#item="row"` binds them all as `row`.
  defp slot_params(nil), do: nil

  defp slot_params(pattern) do
    case OXC.parse("(#{pattern}) => 0", "slot.js") do
      {:ok, %{body: [%{expression: %{params: [param | _]}}]}} -> slot_param(param)
      {:ok, %{body: [%{expression: %{params: %{items: [param | _]}}}]}} -> slot_param(param)
      _ -> nil
    end
  end

  defp slot_param(%{type: :formal_parameter, pattern: pattern}), do: slot_param(pattern)
  defp slot_param(%{type: :identifier, name: name}), do: {:var, name}
  defp slot_param(%{type: :binding_identifier, name: name}), do: {:var, name}

  defp slot_param(%{type: :object_pattern, properties: properties}) do
    {:keys,
     for %{key: key, value: value} <- properties,
         {:var, local} <- [slot_param(value)] do
       {key[:name] || key[:value], local}
     end}
  end

  defp slot_param(_pattern), do: nil
end
