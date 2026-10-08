defmodule PhoenixVapor.Renderer do
  @moduledoc false

  # Renders templates as `%Phoenix.LiveView.Rendered{}` structs.

  alias PhoenixVapor.{ExpressionError, Template}
  alias PhoenixVapor.Compiler.Split
  alias PhoenixVapor.Renderer.{Attrs, Expr, Names, Value}

  @doc """
  Renders a template against assigns.

    * `:root_attrs` — attributes to put on the root element of a template
      compiled with `root_attrs: true`, as a parent's fall through to a child
      component's
  """
  @spec to_rendered(Template.t() | map(), map(), keyword()) :: Phoenix.LiveView.Rendered.t()
  def to_rendered(template, assigns, opts \\ [])

  def to_rendered(%Template{} = template, assigns, opts), do: render(template, assigns, opts)

  # A split straight from `Vize.split_template/2` compiles first.
  def to_rendered(%{statics: _, slots: _} = split, assigns, opts),
    do: split |> Split.compile() |> render(assigns, opts)

  # A nested block, such as a v-if branch or slot content, can be text or
  # several elements, so it isn't marked as a root.
  defp render_block(template, assigns), do: render(template, assigns, root: nil)

  defp render(%Template{statics: statics, slots: slots} = template, assigns, opts) do
    assigns =
      case opts[:root_attrs] do
        nil -> assigns
        attrs -> Map.put(assigns, :__vapor_attrs__, attrs)
      end

    # `__changed__: nil`, or none, means every slot renders, as in LiveView:
    # a session replayer renders a recorded moment that way.
    dynamic = fn track_changes? ->
      changed =
        case assigns do
          %{__changed__: %{} = changed} when track_changes? ->
            MapSet.new(Map.keys(changed), &to_string/1)

          _ ->
            nil
        end

      Enum.map(slots, fn slot ->
        if changed && not slot_changed?(slot, changed) do
          nil
        else
          eval_slot!(slot, assigns, template)
        end
      end)
    end

    %Phoenix.LiveView.Rendered{
      static: statics,
      dynamic: dynamic,
      fingerprint: template.fingerprint || Template.fingerprint(statics, slots),
      root: Keyword.get(opts, :root, true)
    }
  end

  # An expression that can't be evaluated raises with where it is.
  defp eval_slot!(slot, assigns, template) do
    eval_slot(slot, assigns)
  rescue
    error in ExpressionError ->
      reraise %{
                error
                | file: error.file || template.file,
                  position: error.position || slot[:position]
              },
              __STACKTRACE__
  end

  # Every root assign key a template's expressions read, for callers that need
  # the set at compile time.
  @spec assign_keys(Template.t()) :: [String.t()]
  def assign_keys(%Template{} = template) do
    template
    |> exprs()
    |> Enum.flat_map(&Expr.assign_keys/1)
    |> Enum.uniq()
  end

  # The names a template's expressions read, with `props.x` read as `x`, so a
  # caller can tell which props it needs. `props` itself is among them only
  # when an expression reads it whole.
  @spec reads(Template.t()) :: [String.t()]
  def reads(%Template{} = template) do
    template
    |> exprs()
    |> Enum.flat_map(fn
      {tag, _source, node, _keys} when tag in [:expr, :js] and is_map(node) ->
        for name <- PhoenixVapor.JS.FreeNames.of(node, props: true) do
          with "props." <> prop <- name, do: prop
        end

      expr ->
        Expr.assign_keys(expr)
    end)
    |> Enum.uniq()
  end

  # The template's expressions and those of the package components folded
  # into it, whose markup depends on them.
  defp exprs(template),
    do: Enum.map(Template.exprs(template), &elem(&1, 0)) ++ Template.folded(template)

  # ── Slot evaluation ──

  defp eval_slot(%{kind: :text, value: value}, assigns),
    do: value |> Expr.eval(assigns) |> Value.display() |> Attrs.escape()

  # A package component rendered at compile time, with the template's own
  # content inside it.
  defp eval_slot(%{kind: :fragment, template: template}, assigns),
    do: render_block(template, assigns)

  # One rendered at compile time for each value of the expressions its props
  # read, looked up by their values.
  defp eval_slot(%{kind: :fragments, inputs: inputs, table: table}, assigns) do
    values = Enum.map(inputs, &(&1 |> Expr.eval(assigns) |> Expr.literal()))

    case Map.fetch(table, values) do
      {:ok, template} ->
        render_block(template, assigns)

      :error ->
        raise PhoenixVapor.ExpressionError,
          expression: Enum.map_join(inputs, ", ", &elem(&1, 1)),
          reason:
            "#{Enum.map_join(Enum.zip(inputs, values), ", ", fn {input, value} -> "`#{elem(input, 1)}` is #{inspect(value)}" end)}, " <>
              "which its type doesn't allow"
    end
  end

  defp eval_slot(%{kind: :html, value: value}, assigns),
    do: value |> Expr.eval(assigns) |> Value.display()

  defp eval_slot(%{kind: :attr} = slot, assigns) do
    name = slot.name || to_string(Expr.eval(slot.name_value, assigns))
    value = slot.value && Expr.eval(slot.value, assigns)
    show = if slot.show, do: Expr.eval(slot.show, assigns), else: true

    case name do
      "class" ->
        Attrs.render("class", [[slot.static, value]])

      "style" ->
        Attrs.render("style", [
          [slot.static, value, if(Value.truthy?(show), do: nil, else: "display:none")]
        ])

      name when slot.value == nil ->
        Attrs.render(name, [slot.static])

      name ->
        Attrs.render(name, [value])
    end
  end

  defp eval_slot(%{kind: :spread, value: value}, assigns) do
    value
    |> Expr.eval(assigns)
    |> spread()
    |> Enum.map_join(fn {key, value} -> Attrs.render(key, [value]) end)
  end

  defp eval_slot(%{kind: :model, tag: "textarea", value: value}, assigns),
    do: value |> Expr.eval(assigns) |> Value.display() |> Attrs.escape()

  # An `<option>` inside a `<select v-model>` is selected when its value is
  # the select's, or among them for `<select multiple>`, compared as Vue's
  # `looseEqual` does for plain values.
  defp eval_slot(%{kind: :model, tag: "option"} = slot, assigns) do
    selected = Expr.eval(slot.value, assigns)

    option =
      case slot do
        %{option_value: nil} -> slot.static_value
        %{option_value: value} -> Expr.eval(value, assigns)
      end

    selected? =
      if is_list(selected),
        do: Enum.any?(selected, &Value.loose_equal?(&1, option)),
        else: Value.loose_equal?(selected, option)

    Attrs.render("selected", [selected?])
  end

  defp eval_slot(%{kind: :model} = slot, assigns) do
    value = Expr.eval(slot.value, assigns)

    case slot.type do
      "checkbox" when is_list(value) -> Attrs.render("checked", [slot.static_value in value])
      "checkbox" -> Attrs.render("checked", [Value.truthy?(value)])
      "radio" -> Attrs.render("checked", [value == slot.static_value])
      _type -> Attrs.render("value", [value])
    end
  end

  # A condition the server can't evaluate, because only the browser can or
  # because it reads state this render doesn't have, renders no branch:
  # treating it as false would show the `v-else`, which the browser may not.
  defp eval_slot(%{kind: :if, branches: branches}, assigns) do
    Enum.reduce_while(branches, "", fn %{condition: condition, block: block}, none ->
      cond do
        condition == nil -> {:halt, render_block(block, assigns)}
        match?({:unrendered, _source}, condition) -> {:halt, none}
        Expr.absent?(condition, assigns) -> {:halt, none}
        Value.truthy?(Expr.eval(condition, assigns)) -> {:halt, render_block(block, assigns)}
        true -> {:cont, none}
      end
    end)
  end

  defp eval_slot(%{kind: :for} = slot, assigns) do
    prototype = render_block(slot.block, assigns)

    entries =
      slot.source
      |> Expr.eval(assigns)
      |> loop_items()
      |> Enum.map(fn {item, key, index} ->
        item_assigns =
          assigns
          |> put_assign(slot.value, item)
          |> maybe_put_assign(slot.key, key)
          |> maybe_put_assign(slot.index, index)

        entry_key = if slot.key_prop, do: slot.key_prop |> Expr.eval(item_assigns) |> to_string()

        render_fn = fn _vars_changed, _track_changes? ->
          render_block(slot.block, item_assigns).dynamic.(false)
        end

        {entry_key, %{}, render_fn}
      end)

    %Phoenix.LiveView.Comprehension{
      static: prototype.static,
      has_key?: slot.key_prop != nil,
      entries: entries,
      fingerprint: prototype.fingerprint
    }
  end

  # A component imported from a `.vue` file renders its compiled template with
  # its declared props as assigns. Everything else it's passed falls through to
  # its root element, and its slot content renders with the parent's assigns.
  defp eval_slot(%{kind: :component, component: component} = slot, assigns) do
    {props, attrs} =
      slot.props
      |> eval_props(assigns)
      |> Enum.split_with(fn {key, _value} -> Names.camelize(key) in component.props end)

    props = Map.new(props, fn {key, value} -> {Names.camelize(key), value} end)
    declared = Map.new(component.props, &{&1, Map.get(props, &1)})

    child_assigns =
      declared
      |> Enum.reduce(%{}, fn {name, value}, acc -> put_assign(acc, name, value) end)
      |> Map.put("props", declared)
      |> Map.put(:__vapor_attrs__, attrs ++ listeners(slot.events, component.events))
      |> Map.put(:__vapor_slots__, slot_functions(slot, assigns))
      |> Map.put(:__components__, Map.get(assigns, :__components__, %{}))

    render_block(component.template, child_assigns)
  end

  defp eval_slot(%{kind: :component, name: name} = slot, assigns) do
    comp_assigns =
      slot.props
      |> eval_props(assigns)
      |> Map.new(fn {key, value} -> {Names.existing(key), value} end)
      |> Map.put(:inner_block, inner_block(slot, assigns))

    components = Map.get(assigns, :__components__, %{})

    case Map.get(components, name) || Map.get(components, Names.existing(name)) do
      nil -> ""
      component_fn -> component_fn.(comp_assigns)
    end
  end

  defp eval_slot(%{kind: :slot} = slot, assigns) do
    name = slot.name || to_string(Expr.eval(slot.name_value, assigns))

    slot_props =
      slot.props
      |> eval_props(assigns)
      |> Map.new(fn {key, value} -> {Names.camelize(key), value} end)

    case Map.get(Map.get(assigns, :__vapor_slots__, %{}), name) do
      nil when slot.fallback == nil -> ""
      nil -> render_block(slot.fallback, assigns)
      render -> render.(slot_props)
    end
  end

  defp eval_slot(%{kind: :root_attrs, props: props, show: show}, assigns) do
    own =
      Enum.flat_map(props, fn
        %{name: name, value: nil, name_value: nil} = prop when name != nil ->
          [{name, prop.static}]

        %{name: name, static: static} = prop when name in ["class", "style"] ->
          [{name, [static, Expr.eval(prop.value, assigns)]}]

        prop ->
          eval_props([prop], assigns)
      end)

    own =
      if show && not Value.truthy?(Expr.eval(show, assigns)),
        do: own ++ [{"style", "display:none"}],
        else: own

    own
    |> merge_attrs(Map.get(assigns, :__vapor_attrs__, []))
    |> Enum.map_join(fn {key, value} -> Attrs.render(key, [value]) end)
  end

  # Props as `{name, value}` pairs: a static one keeps its string, a bound one
  # its value, and a `v-bind` object contributes each of its entries.
  defp eval_props(props, assigns) do
    Enum.flat_map(props, fn
      %{name: nil, name_value: nil, value: value} ->
        value |> Expr.eval(assigns) |> spread()

      prop ->
        name = prop.name || to_string(Expr.eval(prop.name_value, assigns))
        value = if prop.value, do: Expr.eval(prop.value, assigns), else: prop.static
        [{name, value}]
    end)
  end

  defp spread(map) when is_map(map),
    do: Enum.map(map, fn {key, value} -> {to_string(key), value} end)

  defp spread(_value), do: []

  # Listeners are functions in Vue; on the server, an `@click="save"` passed
  # to a component becomes `phx-click="save"` on its root, like on an element.
  defp listeners(events, true) do
    for %{name: name, value: value} <- events,
        name != nil,
        not String.contains?(name, ":"),
        do: {"phx-" <> name, value || name}
  end

  defp listeners(_events, false), do: []

  # Vue's `mergeProps` for a root element and the attributes passed to its
  # component: `class` and `style` combine, and anything else is replaced.
  defp merge_attrs(own, passed) do
    {merged, added} =
      Enum.reduce(passed, {own, []}, fn {key, value}, {merged, added} ->
        case List.keyfind(merged, key, 0) do
          {^key, mine} when key in ["class", "style"] ->
            {List.keyreplace(merged, key, 0, {key, [mine, value]}), added}

          {^key, _mine} ->
            {List.keyreplace(merged, key, 0, {key, value}), added}

          nil ->
            {merged, [{key, value} | added]}
        end
      end)

    merged ++ Enum.reverse(added)
  end

  # Each slot passed to a component, as a function from the props its outlet
  # passes to rendered content.
  defp slot_functions(%{slots: contents}, assigns) do
    Map.new(contents, fn content ->
      name = content.name || to_string(Expr.eval(content.name_value, assigns))

      {name,
       fn slot_props ->
         render_block(content.block, bind_slot_params(assigns, content.params, slot_props))
       end}
    end)
  end

  defp bind_slot_params(assigns, nil, _slot_props), do: assigns

  defp bind_slot_params(assigns, {:var, name}, slot_props),
    do: put_assign(assigns, name, slot_props)

  defp bind_slot_params(assigns, {:keys, keys}, slot_props) do
    Enum.reduce(keys, assigns, fn {key, local}, acc ->
      put_assign(acc, local, Map.get(slot_props, key))
    end)
  end

  # The default slot, for a function component from the `__components__` assign.
  defp inner_block(slot, assigns) do
    case Map.get(slot_functions(slot, assigns), "default") do
      nil ->
        []

      render ->
        [%{__slot__: :inner_block, inner_block: fn _changed, arg -> render.(arg || %{}) end}]
    end
  end

  # `v-for` over a list, a map, or a number, as `{item, key, index}`: Vue binds
  # a list's index as the second alias, and a map's key, with its index third.
  defp loop_items(list) when is_list(list),
    do: list |> Enum.with_index() |> Enum.map(fn {item, i} -> {item, i, nil} end)

  defp loop_items(map) when is_map(map),
    do:
      map |> Enum.with_index() |> Enum.map(fn {{key, value}, i} -> {value, to_string(key), i} end)

  defp loop_items(n) when is_integer(n) and n > 0, do: Enum.map(1..n, &{&1, &1 - 1, nil})
  defp loop_items(_value), do: []

  defp maybe_put_assign(assigns, nil, _value), do: assigns
  defp maybe_put_assign(assigns, name, value), do: put_assign(assigns, name, value)

  # Expressions look up an existing atom key first, then the string.
  defp put_assign(assigns, name, value) do
    case Names.existing(name) do
      key when is_atom(key) -> assigns |> Map.put(name, value) |> Map.put(key, value)
      _name -> Map.put(assigns, name, value)
    end
  end

  # ── Change tracking ──

  # A slot re-renders when anything it reads changes, including what the
  # blocks inside it read.
  # The keys are stored when compiling; see `PhoenixVapor.Template.put_keys/1`.
  defp slot_changed?(%{keys: keys}, changed), do: Enum.any?(keys, &MapSet.member?(changed, &1))

  # ── Helpers ──

  @doc """
  The attributes reactive mode's client patcher reads from a template's root
  element: the statics, to locate each slot, and each slot's attribute name,
  since an attribute slot is the whole attribute. The root's own attributes
  are one slot, `""`, which the patcher leaves to LiveView.
  """
  @spec vapor_metadata(Template.t()) :: [{String.t(), String.t()}]
  def vapor_metadata(%Template{statics: statics, slots: slots}) do
    [
      {"data-vapor", ""},
      {"data-vapor-statics", Jason.encode!(statics)},
      {"data-vapor-keys", Jason.encode!(Enum.map(slots, &attribute_name/1))}
    ]
  end

  defp attribute_name(%{kind: :attr, name: name}), do: name

  defp attribute_name(%{kind: :model, tag: "input", type: type})
       when type in ["checkbox", "radio"], do: "checked"

  defp attribute_name(%{kind: :model, tag: "input"}), do: "value"
  defp attribute_name(%{kind: :model, tag: "option"}), do: "selected"
  defp attribute_name(%{kind: :root_attrs}), do: ""
  defp attribute_name(_slot), do: nil
end
