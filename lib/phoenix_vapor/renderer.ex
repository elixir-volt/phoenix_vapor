defmodule PhoenixVapor.Renderer do
  @moduledoc false

  alias PhoenixVapor.Expr

  @doc false
  def inject_scope_id(%Phoenix.LiveView.Rendered{static: static} = rendered, scope_id) do
    case static do
      [first | rest] ->
        injected =
          Regex.replace(~r/<([a-zA-Z][a-zA-Z0-9]*)/, first, "<\\1 #{scope_id}", global: false)

        %{rendered | static: [injected | rest]}

      _ ->
        rendered
    end
  end

  @spec to_rendered(map(), map(), keyword()) :: Phoenix.LiveView.Rendered.t()
  def to_rendered(split, assigns, opts \\ [])

  def to_rendered(%{statics: statics, slots: slots}, assigns, opts) do
    split_to_rendered(statics, slots, assigns, opts)
  end

  @doc false
  def split_to_rendered(statics, slots, assigns, opts \\ []) do
    fingerprint = compute_fingerprint(statics, slots)

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
      split_to_rendered(pos.statics, pos.slots, assigns)
    else
      case neg do
        nil ->
          ""

        %{kind: :if_node} = nested_if ->
          eval_slot(nested_if, assigns)

        %{statics: statics, slots: slots} ->
          split_to_rendered(statics, slots, assigns)
      end
    end
  end

  defp eval_slot(%{kind: :for_node, source: source, value: value_name, render: render_split, key_prop: key_prop}, assigns) do
    items = Expr.eval(source, assigns) || []

    dummy_assigns = build_item_assigns(assigns, value_name, %{})
    prototype = split_to_rendered(render_split.statics, render_split.slots, dummy_assigns)
    static_parts = prototype.static
    fingerprint = prototype.fingerprint

    entries =
      Enum.map(items, fn item ->
        item_assigns = build_item_assigns(assigns, value_name, item)

        key = if key_prop, do: Expr.eval(key_prop, item_assigns) |> to_string()

        render_fn = fn _vars_changed, _track_changes? ->
          rendered = split_to_rendered(render_split.statics, render_split.slots, item_assigns)
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

  defp any_key_changed?(:all, _), do: true

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
        ~s( data-vapor data-vapor-statics="#{Phoenix.HTML.Engine.html_escape(statics_json)}")

      injected =
        Regex.replace(~r/<([a-zA-Z][a-zA-Z0-9-]*)/, first, "<\\1#{attr}", global: false)

      [injected | rest]
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
