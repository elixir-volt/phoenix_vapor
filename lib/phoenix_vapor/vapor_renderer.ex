defmodule PhoenixVapor.VaporRenderer do
  @moduledoc false

  alias PhoenixVapor.Expr

  @doc """
  Convert a Vize vapor split into a `%Phoenix.LiveView.VaporRendered{}`.

  The result plugs directly into the first-class Vapor render mode
  in the LiveView fork — schema-driven direct DOM patching with
  explicit slot, branch, and list semantics.
  """
  @spec to_vapor_rendered(map(), map()) :: Phoenix.LiveView.VaporRendered.t()
  def to_vapor_rendered(%{statics: statics, slots: slots} = split, assigns) do
    schema = build_schema(statics, slots)
    html = render_html(split, assigns)
    fingerprint = compute_fingerprint(statics, slots)

    dynamic = fn track_changes? ->
      changed =
        case assigns do
          %{__changed__: changed} when track_changes? -> changed
          _ -> nil
        end

      build_patch(slots, assigns, changed, 0)
    end

    %Phoenix.LiveView.VaporRendered{
      fingerprint: fingerprint,
      html: html,
      schema: schema,
      dynamic: dynamic,
      root: true
    }
  end

  # ── Schema generation ──

  defp build_schema(statics, slots) do
    children = build_schema_children(statics, slots, 0)
    %{k: "root", children: children}
  end

  defp build_schema_children(statics, slots, slot_offset) do
    # Walk statics and interleave slot schema nodes.
    # Each static segment may contain element structure; each gap is a slot.
    statics
    |> Enum.with_index()
    |> Enum.flat_map(fn {static, i} ->
      static_nodes = if static != "", do: [%{k: "text", v: static}], else: []
      slot_idx = i + slot_offset

      slot_node =
        if i < length(slots) do
          slot = Enum.at(slots, i)
          [slot_to_schema(slot, slot_idx)]
        else
          []
        end

      static_nodes ++ slot_node
    end)
  end

  defp slot_to_schema(%{kind: :set_text} = slot, id) do
    %{k: "slot", id: id, m: "text"}
  end

  defp slot_to_schema(%{kind: :set_prop} = _slot, id) do
    %{k: "slot", id: id, m: "attr"}
  end

  defp slot_to_schema(%{kind: :set_html} = _slot, id) do
    %{k: "slot", id: id, m: "html"}
  end

  defp slot_to_schema(%{kind: :v_show} = _slot, id) do
    %{k: "slot", id: id, m: "attr"}
  end

  defp slot_to_schema(%{kind: :v_model} = _slot, id) do
    %{k: "slot", id: id, m: "attr"}
  end

  defp slot_to_schema(%{kind: :if_node} = slot, id) do
    variants = build_branch_variants(slot, 0)

    %{
      k: "branch",
      id: "b#{id}",
      variants: variants
    }
  end

  defp slot_to_schema(%{kind: :for_node, render: render} = _slot, id) do
    item_schema = build_item_schema(render)
    item_html = build_item_html_template(render)

    %{
      k: "list",
      id: "l#{id}",
      keyed: true,
      item: Map.put(item_schema, :html, item_html)
    }
  end

  defp slot_to_schema(_slot, id) do
    %{k: "slot", id: id, m: "text"}
  end

  defp build_branch_variants(nil, _idx), do: %{}

  defp build_branch_variants(%{kind: :if_node} = node, idx) do
    pos_schema = build_variant_schema(node.positive)
    pos_html = render_variant_html(node.positive)

    variants = %{idx => Map.put(pos_schema, :html, pos_html)}

    case node.negative do
      nil ->
        # v-if with no else — add empty variant
        Map.put(variants, idx + 1, %{k: "root", children: [], html: ""})

      %{kind: :if_node} = nested ->
        Map.merge(variants, build_branch_variants(nested, idx + 1))

      neg ->
        neg_schema = build_variant_schema(neg)
        neg_html = render_variant_html(neg)
        Map.put(variants, idx + 1, Map.put(neg_schema, :html, neg_html))
    end
  end

  defp build_variant_schema(%{statics: statics, slots: slots}) do
    children = build_schema_children(statics, slots, 0)
    %{k: "root", children: children}
  end

  defp build_item_schema(%{statics: statics, slots: slots}) do
    children = build_schema_children(statics, slots, 0)
    %{k: "root", children: children}
  end

  defp build_item_html_template(%{statics: statics}) do
    Enum.join(statics, "")
  end

  defp render_variant_html(%{statics: statics}) do
    Enum.join(statics, "")
  end

  # ── Patch generation ──

  defp build_patch(slots, assigns, changed, offset) do
    {patch, _next_offset} =
      Enum.reduce(slots, {%{}, offset}, fn slot, {patch, idx} ->
        case slot do
          %{kind: kind} when kind in [:set_text, :set_prop] ->
            if changed && not slot_changed?(slot, changed) do
              {patch, idx + 1}
            else
              value = Expr.eval_values(slot.values, assigns) |> to_string()
              put_slot(patch, idx, value, idx + 1)
            end

          %{kind: :set_html, value: expr} ->
            if changed && not slot_changed?(slot, changed) do
              {patch, idx + 1}
            else
              value = Expr.eval(expr, assigns) |> to_string()
              put_slot(patch, idx, value, idx + 1)
            end

          %{kind: :v_show, value: expr} ->
            if changed && not slot_changed?(slot, changed) do
              {patch, idx + 1}
            else
              value = if Expr.eval(expr, assigns), do: "", else: "display: none"
              put_slot(patch, idx, value, idx + 1)
            end

          %{kind: :v_model, value: expr} ->
            if changed && not slot_changed?(slot, changed) do
              {patch, idx + 1}
            else
              value =
                Expr.eval(expr, assigns)
                |> to_string()
                |> Phoenix.HTML.html_escape()
                |> Phoenix.HTML.safe_to_string()

              put_slot(patch, idx, value, idx + 1)
            end

          %{kind: :if_node} = node ->
            branch_id = "b#{idx}"
            {active, active_split} = resolve_active_branch(node, assigns)
            inner_patch = build_patch(active_split.slots, assigns, changed, 0)

            branch_patch = %{active: active, patch: inner_patch}
            patch = put_in_nested(patch, [:branches, branch_id], branch_patch)
            {patch, idx + 1}

          %{kind: :for_node, source: source, value: value_name, render: render, key_prop: key_prop} ->
            list_id = "l#{idx}"
            items = Expr.eval(source, assigns) || []

            ops =
              Enum.with_index(items)
              |> Enum.map(fn {item, pos} ->
                item_assigns = build_item_assigns(assigns, value_name, item)
                key = if key_prop, do: Expr.eval(key_prop, item_assigns) |> to_string(), else: to_string(pos)
                item_patch = build_patch(render.slots, item_assigns, nil, 0)
                {:insert, key, pos, item_patch}
              end)

            patch = put_in_nested(patch, [:lists, list_id], ops)
            {patch, idx + 1}

          _ ->
            {patch, idx + 1}
        end
      end)

    patch
  end

  defp put_slot(patch, idx, value, next_idx) do
    slots = Map.get(patch, :slots, %{})
    {Map.put(patch, :slots, Map.put(slots, idx, value)), next_idx}
  end

  defp put_in_nested(patch, [key1, key2], value) do
    inner = Map.get(patch, key1, %{})
    Map.put(patch, key1, Map.put(inner, key2, value))
  end

  defp resolve_active_branch(%{kind: :if_node, condition: cond_expr, positive: pos, negative: neg}, assigns) do
    if Expr.eval(cond_expr, assigns) do
      {0, pos}
    else
      case neg do
        nil -> {1, %{slots: [], statics: [""]}}
        %{kind: :if_node} = nested -> resolve_active_branch_chain(nested, assigns, 1)
        neg_split -> {1, neg_split}
      end
    end
  end

  defp resolve_active_branch_chain(%{kind: :if_node, condition: cond_expr, positive: pos, negative: neg}, assigns, idx) do
    if Expr.eval(cond_expr, assigns) do
      {idx, pos}
    else
      case neg do
        nil -> {idx + 1, %{slots: [], statics: [""]}}
        %{kind: :if_node} = nested -> resolve_active_branch_chain(nested, assigns, idx + 1)
        neg_split -> {idx + 1, neg_split}
      end
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

  defp slot_changed?(_, _), do: true

  defp any_key_changed?(:all, _), do: true

  defp any_key_changed?(keys, changed) when is_list(keys) do
    Enum.any?(keys, &Map.has_key?(changed, &1))
  end

  # ── HTML rendering ──

  defp render_html(%{statics: statics, slots: slots}, assigns) do
    rendered = PhoenixVapor.Renderer.to_rendered(%{statics: statics, slots: slots}, assigns)
    Phoenix.HTML.Safe.to_iodata(rendered) |> IO.iodata_to_binary()
  end

  defp compute_fingerprint(statics, slots) do
    <<fingerprint::8*16>> =
      [statics | slots]
      |> :erlang.term_to_binary()
      |> :erlang.md5()

    fingerprint
  end

  defp build_item_assigns(assigns, value_name, item) do
    assigns
    |> Map.put(value_name, item)
    |> Map.put(String.to_atom(value_name), item)
  end
end
