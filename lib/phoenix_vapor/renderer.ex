defmodule PhoenixVapor.Renderer do
  @moduledoc false

  alias PhoenixVapor.{Attrs, Expr, Names}

  def inject_scope_id(%Phoenix.LiveView.Rendered{static: static} = rendered, scope_id) do
    case static do
      [first | rest] ->
        %{rendered | static: [inject_attr_into_first_tag(first, scope_id) | rest]}

      _ ->
        rendered
    end
  end

  # A tag name ends at whitespace, "/" or ">", so the attribute goes right
  # after it; attribute values may contain ">".
  defp inject_attr_into_first_tag(html, attr) do
    case Regex.run(~r{\A\s*<[a-zA-Z][^\s/>]*}, html) do
      [open] ->
        open <>
          " " <> attr <> binary_part(html, byte_size(open), byte_size(html) - byte_size(open))

      nil ->
        html
    end
  end

  @spec to_rendered(map(), map(), keyword()) :: Phoenix.LiveView.Rendered.t()
  def to_rendered(split, assigns, opts \\ [])

  def to_rendered(%{statics: statics, slots: slots} = split, assigns, opts) do
    split_to_rendered(statics, slots, assigns, [fingerprint: split[:fingerprint]] ++ opts)
  end

  # Parses every expression in a split, renders its bindings, and computes each
  # fingerprint, for splits compiled into a module. Rendering accepts either
  # form.
  #
  # Vize leaves events and v-model unrendered and reports where each element's
  # start tag ends. LiveView handles them through phx-* attributes; pass
  # `events: false` when client code handles the template's events instead.
  @spec compile(map(), keyword()) :: map()
  def compile(%{statics: statics, slots: slots} = split, opts \\ []) do
    statics = render_bindings(statics, Map.get(split, :bindings, []), opts)

    %{split | statics: statics, slots: Enum.map(slots, &compile_slot(&1, opts))}
    |> Map.put(:bindings, [])
    |> Map.put(:fingerprint, compute_fingerprint(statics, slots))
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

  defp binding_attribute(%{kind: :set_event, node: node}, true) do
    event = event_name(node.key)
    ~s( phx-#{event}="#{Phoenix.HTML.Engine.html_escape(node.value || event)}")
  end

  defp binding_attribute(%{kind: :directive, node: %{name: "model", value: value}}, true),
    do: ~s( phx-change="#{Phoenix.HTML.Engine.html_escape(value <> "_changed")}")

  defp binding_attribute(_binding, true), do: nil

  defp event_name({:static_, name}), do: name
  defp event_name(name) when is_binary(name), do: name

  defp compile_slot(%{kind: kind, values: values} = slot, _opts)
       when kind in [:set_text, :set_prop],
       do: %{slot | values: Enum.map(values, &Expr.compile/1)}

  defp compile_slot(%{kind: kind, value: expr} = slot, _opts)
       when kind in [:set_html, :v_show, :v_model],
       do: %{slot | value: Expr.compile(expr)}

  defp compile_slot(%{kind: :if_node, condition: expr, positive: pos, negative: neg} = slot, opts) do
    %{
      slot
      | condition: Expr.compile(expr),
        positive: compile(pos, opts),
        negative: compile_branch(neg, opts)
    }
  end

  defp compile_slot(
         %{kind: :for_node, source: source, key_prop: key, render: render} = slot,
         opts
       ) do
    %{
      slot
      | source: Expr.compile(source),
        key_prop: key && Expr.compile(key),
        render: compile(render, opts)
    }
  end

  defp compile_slot(%{kind: :create_component, props: props} = slot, opts) do
    slot_fns =
      for slot_fn <- Map.get(slot, :slots, []) do
        %{slot_fn | render: compile(slot_fn.render, opts)}
        |> Map.put(:params, slot_params(slot_fn.fn_exp))
      end

    %{slot | props: compile_props(props)} |> Map.put(:slots, slot_fns)
  end

  defp compile_slot(%{kind: :slot_outlet, props: props, fallback: fallback} = slot, opts),
    do: %{slot | props: compile_props(props), fallback: compile_branch(fallback, opts)}

  defp compile_slot(%{kind: :root_attrs, props: props} = slot, _opts),
    do: %{slot | props: compile_props(props)}

  defp compile_slot(slot, _opts), do: slot

  defp compile_props(props),
    do: Enum.map(props, &%{&1 | values: Enum.map(&1.values, fn v -> Expr.compile(v) end)})

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

  defp compile_branch(nil, _opts), do: nil
  defp compile_branch(%{kind: _} = slot, opts), do: compile_slot(slot, opts)
  defp compile_branch(split, opts), do: compile(split, opts)

  # A nested block, such as a v-if branch or slot content, can be text or
  # several elements, so it isn't marked as a root.
  defp render_split(split, assigns),
    do:
      split_to_rendered(split.statics, split.slots, assigns,
        fingerprint: split[:fingerprint],
        root: nil
      )

  def split_to_rendered(statics, slots, assigns, opts \\ []) do
    fingerprint = opts[:fingerprint] || compute_fingerprint(statics, slots)

    dynamic = fn track_changes? ->
      changed =
        case assigns do
          %{__changed__: changed} when track_changes? ->
            MapSet.new(Map.keys(changed), &to_string/1)

          _ ->
            nil
        end

      Enum.map(slots, fn slot ->
        if changed && not slot_changed?(slot, changed) do
          nil
        else
          eval_slot(slot, assigns)
        end
      end)
    end

    statics =
      if Keyword.get(opts, :vapor_metadata, false) do
        inject_vapor_metadata(statics, slots)
      else
        statics
      end

    %Phoenix.LiveView.Rendered{
      static: statics,
      dynamic: dynamic,
      fingerprint: fingerprint,
      root: Keyword.get(opts, :root, true)
    }
  end

  # Every root assign key a split's expressions read, for callers that need the
  # set at compile time.
  @spec assign_keys(map()) :: [String.t()]
  def assign_keys(%{slots: slots}) do
    slots |> Enum.flat_map(&slot_assign_keys/1) |> Enum.uniq()
  end

  defp slot_assign_keys(%{kind: kind, values: values}) when kind in [:set_text, :set_prop],
    do: Expr.values_assign_keys(values)

  defp slot_assign_keys(%{kind: kind, value: expr}) when kind in [:set_html, :v_show, :v_model],
    do: Expr.assign_keys(expr)

  defp slot_assign_keys(%{kind: :if_node, condition: expr, positive: pos, negative: neg}) do
    Expr.assign_keys(expr) ++ assign_keys(pos) ++ if(neg, do: slot_or_split_keys(neg), else: [])
  end

  defp slot_assign_keys(%{kind: :for_node, source: source, render: render}),
    do: Expr.assign_keys(source) ++ assign_keys(render)

  defp slot_assign_keys(%{kind: :create_component, props: props} = slot) do
    Enum.flat_map(props, &Expr.values_assign_keys(&1.values)) ++
      Enum.flat_map(Map.get(slot, :slots, []), &assign_keys(&1.render))
  end

  defp slot_assign_keys(_slot), do: []

  defp slot_or_split_keys(%{kind: _} = slot), do: slot_assign_keys(slot)
  defp slot_or_split_keys(split), do: assign_keys(split)

  # ── Slot evaluation ──

  defp eval_slot(%{kind: :set_text, values: values}, assigns) do
    Expr.eval_values(values, assigns)
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end

  defp eval_slot(%{kind: :set_html, value: value}, assigns) do
    Expr.eval(value, assigns) |> to_string()
  end

  defp eval_slot(%{kind: :set_prop, key: key, values: values}, assigns) do
    Attrs.render(key, Enum.map(values, &Expr.eval(&1, assigns)))
  end

  defp eval_slot(%{kind: :v_show, value: expr}, assigns) do
    if Expr.eval(expr, assigns), do: "", else: "display: none"
  end

  defp eval_slot(%{kind: :v_model, value: expr}, assigns) do
    Expr.eval(expr, assigns)
    |> to_string()
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end

  defp eval_slot(%{kind: :if_node, condition: cond_expr, positive: pos, negative: neg}, assigns) do
    if Expr.eval(cond_expr, assigns) do
      render_split(pos, assigns)
    else
      case neg do
        nil ->
          ""

        %{kind: :if_node} = nested_if ->
          eval_slot(nested_if, assigns)

        split ->
          render_split(split, assigns)
      end
    end
  end

  defp eval_slot(
         %{
           kind: :for_node,
           source: source,
           value: value_name,
           render: item_split,
           key_prop: key_prop
         },
         assigns
       ) do
    items = Expr.eval(source, assigns) || []

    dummy_assigns = put_assign(assigns, value_name, %{})
    prototype = render_split(item_split, dummy_assigns)
    static_parts = prototype.static
    fingerprint = prototype.fingerprint

    entries =
      Enum.map(items, fn item ->
        item_assigns = put_assign(assigns, value_name, item)

        key = if key_prop, do: Expr.eval(key_prop, item_assigns) |> to_string()

        render_fn = fn _vars_changed, _track_changes? ->
          rendered = render_split(item_split, item_assigns)
          rendered.dynamic.(false)
        end

        {key, %{}, render_fn}
      end)

    %Phoenix.LiveView.Comprehension{
      static: static_parts,
      has_key?: key_prop != nil,
      entries: entries,
      fingerprint: fingerprint
    }
  end

  # A component imported from a `.vue` file renders its compiled template with
  # its declared props as assigns. Everything else it's passed falls through to
  # its root element, and its slot content renders with the parent's assigns.
  defp eval_slot(%{kind: :create_component, component: component} = slot, assigns) do
    {props, attrs} =
      slot.props
      |> Enum.map(&{extract_key(&1.key), component_prop(&1.values, assigns)})
      |> Enum.split_with(fn {key, _value} -> camelize(key) in component.props end)

    props = Map.new(props, fn {key, value} -> {camelize(key), value} end)
    declared = Map.new(component.props, &{&1, Map.get(props, &1)})

    child_assigns =
      declared
      |> Enum.reduce(%{}, fn {name, value}, acc -> put_assign(acc, name, value) end)
      |> Map.put("props", declared)
      |> Map.put(:__vapor_attrs__, fallthrough(attrs, slot.props, component.events))
      |> Map.put(:__vapor_slots__, slot_functions(slot, assigns))
      |> Map.put(:__components__, Map.get(assigns, :__components__, %{}))

    render_split(component.split, child_assigns)
  end

  defp eval_slot(%{kind: :create_component, tag: tag, props: props} = slot, assigns) do
    comp_assigns =
      Enum.reduce(props, %{}, fn prop, acc ->
        key_name = extract_key(prop.key)
        Map.put(acc, Names.existing(key_name), component_prop(prop.values, assigns))
      end)
      |> Map.put(:inner_block, inner_block(slot, assigns))

    components = Map.get(assigns, :__components__, %{})

    case Map.get(components, tag) || Map.get(components, Names.existing(tag)) do
      nil -> ""
      component_fn -> component_fn.(comp_assigns)
    end
  end

  defp eval_slot(%{kind: :slot_outlet, name: name, props: props, fallback: fallback}, assigns) do
    slot_props =
      Map.new(props, &{camelize(extract_key(&1.key)), component_prop(&1.values, assigns)})

    case Map.get(Map.get(assigns, :__vapor_slots__, %{}), Expr.eval(name, assigns)) do
      nil -> render_branch(fallback, assigns)
      render -> render.(slot_props)
    end
  end

  defp eval_slot(%{kind: :root_attrs, props: props}, assigns) do
    own = Enum.map(props, &{&1.key, component_prop(&1.values, assigns)})

    own
    |> merge_attrs(Map.get(assigns, :__vapor_attrs__, []))
    |> Enum.map_join(fn {key, value} -> Attrs.render(key, [value]) end)
  end

  # A prop bound to one expression keeps its value; Vue passes `:items="list"`
  # as the list itself, not its string form.
  defp component_prop([single], assigns), do: Expr.eval(single, assigns)
  defp component_prop(values, assigns), do: Expr.eval_values(values, assigns)

  # Listeners are functions in Vue; on the server, an `@click="save"` passed
  # to a component becomes `phx-click="save"` on its root, like on an element.
  defp fallthrough(attrs, props, events?) do
    sources = Map.new(props, &{extract_key(&1.key), &1.values})

    Enum.flat_map(attrs, fn {key, value} ->
      case Regex.run(~r/\Aon([A-Z].*)\z/, key) do
        [_, event] when events? ->
          [{"phx-" <> String.downcase(event), event_source(sources[key])}]

        [_, _event] ->
          []

        nil ->
          [{key, value}]
      end
    end)
  end

  defp event_source([{:expr, source, _node, _keys}]), do: source
  defp event_source([{:static_, source}]), do: source
  defp event_source(_values), do: nil

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
  defp slot_functions(slot, assigns) do
    Map.new(Map.get(slot, :slots, []), fn slot_fn ->
      {Expr.eval(slot_fn.name, assigns),
       fn slot_props ->
         render_split(slot_fn.render, bind_slot_params(assigns, slot_fn.params, slot_props))
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

  defp render_branch(nil, _assigns), do: ""
  defp render_branch(%{kind: _} = slot, assigns), do: eval_slot(slot, assigns)
  defp render_branch(split, assigns), do: render_split(split, assigns)

  # Vue matches `side-offset` to a `sideOffset` prop.
  defp camelize(key), do: Regex.replace(~r/-(\w)/, key, fn _, char -> String.upcase(char) end)

  # Expressions look up an existing atom key first, then the string.
  defp put_assign(assigns, name, value) do
    case Names.existing(name) do
      key when is_atom(key) -> assigns |> Map.put(name, value) |> Map.put(key, value)
      _name -> Map.put(assigns, name, value)
    end
  end

  # ── Change tracking ──

  defp slot_changed?(%{kind: kind, values: values}, changed)
       when kind in [:set_text, :set_prop] do
    keys = Expr.values_assign_keys(values)
    any_key_changed?(keys, changed)
  end

  defp slot_changed?(%{kind: kind, value: expr}, changed)
       when kind in [:set_html, :v_show, :v_model] do
    keys = Expr.assign_keys(expr)
    any_key_changed?(keys, changed)
  end

  # A structural slot re-renders when anything its content reads changes, not
  # only its condition or source.
  defp slot_changed?(%{kind: kind} = slot, changed)
       when kind in [:if_node, :for_node, :create_component] do
    slot |> slot_assign_keys() |> any_key_changed?(changed)
  end

  defp slot_changed?(_, _), do: true

  # Expressions name assigns as strings; `changed` holds the changed names.
  defp any_key_changed?(keys, changed) when is_list(keys) do
    Enum.any?(keys, &MapSet.member?(changed, &1))
  end

  # ── Helpers ──

  defp extract_key({:static_, name}), do: name
  defp extract_key(name) when is_binary(name), do: name

  # The loop variable shadows an assign with the same name, so set the atom key
  # too when that atom exists.
  # The client patcher locates slots from the statics; an attribute slot is the
  # whole attribute, so it also needs the attribute's name.
  defp inject_vapor_metadata([first | rest], slots) do
    if String.starts_with?(String.trim_leading(first), "<") do
      statics_json = Jason.encode!([first | rest])
      keys_json = Jason.encode!(Enum.map(slots, &Map.get(&1, :key)))

      attr =
        ~s(data-vapor data-vapor-statics="#{Phoenix.HTML.Engine.html_escape(statics_json)}") <>
          ~s( data-vapor-keys="#{Phoenix.HTML.Engine.html_escape(keys_json)}")

      [inject_attr_into_first_tag(first, attr) | rest]
    else
      [first | rest]
    end
  end

  defp inject_vapor_metadata(static, _slots), do: static

  defp compute_fingerprint(statics, slots) do
    <<fingerprint::8*16>> =
      [statics | slots]
      |> :erlang.term_to_binary()
      |> :erlang.md5()

    fingerprint
  end
end
