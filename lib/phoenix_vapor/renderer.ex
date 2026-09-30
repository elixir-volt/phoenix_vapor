defmodule PhoenixVapor.Renderer do
  @moduledoc false

  alias PhoenixVapor.Expr

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

  # Parses every expression in a split and computes each fingerprint, for
  # splits compiled into a module. Rendering accepts either form.
  @spec compile(map()) :: map()
  def compile(%{statics: statics, slots: slots} = split) do
    %{split | slots: Enum.map(slots, &compile_slot/1)}
    |> Map.put(:fingerprint, compute_fingerprint(statics, slots))
  end

  defp compile_slot(%{kind: kind, values: values} = slot) when kind in [:set_text, :set_prop],
    do: %{slot | values: Enum.map(values, &Expr.compile/1)}

  defp compile_slot(%{kind: kind, value: expr} = slot)
       when kind in [:set_html, :v_show, :v_model],
       do: %{slot | value: Expr.compile(expr)}

  defp compile_slot(%{kind: :if_node, condition: expr, positive: pos, negative: neg} = slot) do
    %{
      slot
      | condition: Expr.compile(expr),
        positive: compile(pos),
        negative: compile_branch(neg)
    }
  end

  defp compile_slot(%{kind: :for_node, source: source, key_prop: key, render: render} = slot) do
    %{
      slot
      | source: Expr.compile(source),
        key_prop: key && Expr.compile(key),
        render: compile(render)
    }
  end

  defp compile_slot(%{kind: :create_component, props: props} = slot),
    do: %{
      slot
      | props: Enum.map(props, &%{&1 | values: Enum.map(&1.values, fn v -> Expr.compile(v) end)})
    }

  defp compile_slot(slot), do: slot

  defp compile_branch(nil), do: nil
  defp compile_branch(%{kind: _} = slot), do: compile_slot(slot)
  defp compile_branch(split), do: compile(split)

  defp render_split(split, assigns),
    do: split_to_rendered(split.statics, split.slots, assigns, fingerprint: split[:fingerprint])

  def split_to_rendered(statics, slots, assigns, opts \\ []) do
    fingerprint = opts[:fingerprint] || compute_fingerprint(statics, slots)

    dynamic = fn track_changes? ->
      changed =
        case assigns do
          %{__changed__: changed} when track_changes? -> changed
          _ -> nil
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
        inject_vapor_metadata(statics)
      else
        statics
      end

    %Phoenix.LiveView.Rendered{
      static: statics,
      dynamic: dynamic,
      fingerprint: fingerprint,
      root: true
    }
  end

  # Every root assign key a split's expressions read, for callers that need the
  # set at compile time.
  @spec assign_keys(map()) :: [atom()]
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

  defp slot_assign_keys(%{kind: :create_component, props: props}),
    do: Enum.flat_map(props, &Expr.values_assign_keys(&1.values))

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

  defp eval_slot(%{kind: :set_prop, values: values}, assigns) do
    Expr.eval_values(values, assigns)
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
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

    dummy_assigns = build_item_assigns(assigns, value_name, %{})
    prototype = render_split(item_split, dummy_assigns)
    static_parts = prototype.static
    fingerprint = prototype.fingerprint

    entries =
      Enum.map(items, fn item ->
        item_assigns = build_item_assigns(assigns, value_name, item)

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

  defp eval_slot(%{kind: :create_component, tag: tag, props: props}, assigns) do
    comp_assigns =
      Enum.reduce(props, %{}, fn prop, acc ->
        key_name = extract_key(prop.key)
        value = Expr.eval_values(prop.values, assigns)
        Map.put(acc, String.to_atom(key_name), value)
      end)

    components = Map.get(assigns, :__components__, %{})

    case Map.get(components, tag) || Map.get(components, String.to_atom(tag)) do
      nil -> ""
      component_fn -> component_fn.(comp_assigns)
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

  defp slot_changed?(%{kind: :if_node, condition: cond_expr}, changed) do
    keys = Expr.assign_keys(cond_expr)
    any_key_changed?(keys, changed)
  end

  defp slot_changed?(%{kind: :for_node, source: source}, changed) do
    keys = Expr.assign_keys(source)
    any_key_changed?(keys, changed)
  end

  defp slot_changed?(%{kind: :create_component, props: props}, changed) do
    keys =
      props
      |> Enum.flat_map(fn prop -> Expr.values_assign_keys(prop.values) end)
      |> Enum.uniq()

    any_key_changed?(keys, changed)
  end

  defp slot_changed?(_, _), do: true

  defp any_key_changed?(keys, changed) when is_list(keys) do
    Enum.any?(keys, &Map.has_key?(changed, &1))
  end

  # ── Helpers ──

  defp extract_key({:static_, name}), do: name
  defp extract_key(name) when is_binary(name), do: name

  defp build_item_assigns(assigns, value_name, item) do
    assigns
    |> Map.put(value_name, item)
    |> Map.put(String.to_atom(value_name), item)
  end

  defp inject_vapor_metadata([first | rest]) do
    if String.starts_with?(String.trim_leading(first), "<") do
      statics_json = Jason.encode!([first | rest])

      attr =
        ~s(data-vapor data-vapor-statics="#{Phoenix.HTML.Engine.html_escape(statics_json)}")

      [inject_attr_into_first_tag(first, attr) | rest]
    else
      [first | rest]
    end
  end

  defp inject_vapor_metadata(static), do: static

  defp compute_fingerprint(statics, slots) do
    <<fingerprint::8*16>> =
      [statics | slots]
      |> :erlang.term_to_binary()
      |> :erlang.md5()

    fingerprint
  end
end
