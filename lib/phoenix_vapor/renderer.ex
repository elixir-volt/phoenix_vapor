defmodule PhoenixVapor.Renderer do
  @moduledoc false

  alias PhoenixVapor.Expr

  @prop_marker "{{__PROP__}}"
  @struct_marker "{{__STRUCT__}}"

  @spec to_rendered(map(), map()) :: Phoenix.LiveView.Rendered.t()

  @doc false
  def inject_scope_id(%Phoenix.LiveView.Rendered{static: static} = rendered, scope_id) do
    case static do
      [first | rest] ->
        # Inject scope attribute into the first opening tag
        injected = Regex.replace(~r/<([a-zA-Z][a-zA-Z0-9]*)/, first, "<\\1 #{scope_id}", global: false)
        %{rendered | static: [injected | rest]}

      _ ->
        rendered
    end
  end

  def to_rendered(ir, assigns, opts \\ [])

  def to_rendered(%{block: block, templates: templates} = ir, assigns, opts) do
    etm = ir[:element_template_map] || []
    etm_map = Map.new(etm)
    block_to_rendered(block, templates, etm_map, assigns, opts)
  end

  @doc false
  def block_to_rendered(block, templates, etm_map, assigns, opts \\ []) do
    %{operations: operations, effects: effects, returns: returns} = block

    template_html = resolve_template(returns, templates, etm_map)

    all_effects = List.flatten(effects)
    text_effects = Enum.filter(all_effects, &(&1.kind == :set_text))
    prop_effects = Enum.filter(all_effects, &(&1.kind == :set_prop))
    html_effects = Enum.filter(all_effects, &(&1.kind == :set_html))

    structural_ops =
      Enum.filter(operations, fn
        %{kind: kind} when kind in [:if_node, :for_node, :create_component] -> true
        _ -> false
      end)

    event_ops =
      Enum.filter(operations, fn
        %{kind: :set_event} -> true
        _ -> false
      end)

    directive_ops =
      Enum.filter(operations, fn
        %{kind: :directive} -> true
        _ -> false
      end)

    props_by_element = Enum.group_by(prop_effects, & &1.element)

    # Build element ID → tag position mapping within this template
    elem_to_tag = build_element_tag_map(returns, operations, template_html)

    # Phase 0: Inject static event attributes (phx-click, etc.) and
    # v-show/v-model directives into the template before splitting
    template_html = inject_events(template_html, event_ops, elem_to_tag)

    {static, dynamic_specs} =
      build_static_dynamic(template_html, text_effects, props_by_element, html_effects, structural_ops, directive_ops, templates, etm_map, elem_to_tag)

    fingerprint = compute_fingerprint(static, block)

    dynamic = fn track_changes? ->
      changed =
        case assigns do
          %{__changed__: changed} when track_changes? -> changed
          _ -> nil
        end

      Enum.map(dynamic_specs, fn spec ->
        if changed && not spec_changed?(spec, changed) do
          nil
        else
          eval_spec(spec, assigns, templates, etm_map)
        end
      end)
    end

    static =
      if Keyword.get(opts, :vapor_metadata, false) do
        inject_vapor_metadata(static)
      else
        static
      end

    %Phoenix.LiveView.Rendered{
      static: static,
      dynamic: dynamic,
      fingerprint: fingerprint,
      root: true
    }
  end

  defp inject_vapor_metadata([first | rest] = static) do
    # Only inject if the first static starts with a tag
    if String.starts_with?(String.trim_leading(first), "<") do
      statics_json = Jason.encode!(static)
      attr = ~s( data-vapor data-vapor-statics="#{Phoenix.HTML.Engine.html_escape(statics_json)}")
      injected = Regex.replace(~r/<([a-zA-Z][a-zA-Z0-9-]*)/, first, "<\\1#{attr}", global: false)
      [injected | rest]
    else
      static
    end
  end

  defp inject_vapor_metadata(static), do: static

  # Inject event handlers as static phx-* attributes into the template HTML.
  # @click="handler" → phx-click="handler"
  # @submit.prevent="handler" → phx-submit="handler"
  defp inject_events(html, [], _elem_to_tag), do: html

  defp inject_events(html, event_ops, elem_to_tag) do
    Enum.reduce(event_ops, html, fn event, h ->
      tag_pos = Map.get(elem_to_tag, event.element, event.element)
      event_name = extract_key(event.key)
      handler = if is_binary(event.value), do: event.value, else: extract_key(event.value)

      inject_attr_into_nth_tag(h, tag_pos, " phx-#{event_name}=\"#{handler}\"")
    end)
  end

  # Build a mapping from element IDs to their tag position (0-indexed)
  # within the template HTML string.
  #
  # The root element(s) from `returns` are the outermost tags.
  # child_ref/next_ref operations describe the tree structure.
  defp build_element_tag_map(returns, operations, template_html) do
    # Count opening tags in the template
    refs =
      operations
      |> Enum.filter(fn
        %{kind: kind} when kind in [:child_ref, :next_ref] -> true
        _ -> false
      end)

    if refs == [] and length(returns) == 1 do
      # Single root element, no children referenced by effects
      %{hd(returns) => 0}
    else
      # Build tree: root elements are at known positions, children navigate from there
      # The root element is at tag position 0 (for single-root templates)
      root_map =
        returns
        |> Enum.with_index()
        |> Map.new(fn {elem_id, idx} -> {elem_id, idx} end)

      resolve_refs(root_map, refs, template_html)
    end
  end

  defp resolve_refs(elem_map, refs, template_html) do
    # Parse the template into a tree structure to understand nesting
    tag_tree = parse_tag_tree(template_html)

    new_map =
      Enum.reduce(refs, elem_map, fn
        %{kind: :child_ref, child_id: child_id, parent_id: parent_id, offset: offset}, acc ->
          case Map.get(acc, parent_id) do
            nil ->
              acc

            parent_tag_pos ->
              child_tag_pos = find_nth_child_tag(tag_tree, parent_tag_pos, offset)

              if child_tag_pos do
                Map.put(acc, child_id, child_tag_pos)
              else
                acc
              end
          end

        %{kind: :next_ref, child_id: child_id, parent_id: prev_id, offset: offset}, acc ->
          case Map.get(acc, prev_id) do
            nil ->
              acc

            prev_tag_pos ->
              sibling_tag_pos = find_nth_sibling_tag(tag_tree, prev_tag_pos, offset)

              if sibling_tag_pos do
                Map.put(acc, child_id, sibling_tag_pos)
              else
                acc
              end
          end
      end)

    if map_size(new_map) > map_size(elem_map) do
      resolve_refs(new_map, refs, template_html)
    else
      new_map
    end
  end

  # Parse HTML into a flat list of tag entries with parent/child relationships.
  # Returns [{tag_pos, tag_name, parent_tag_pos, child_index_in_parent}]
  defp parse_tag_tree(html) do
    parse_tag_tree(html, 0, [], [], -1)
  end

  defp parse_tag_tree("", _pos, entries, _stack, _tag_counter) do
    Enum.reverse(entries)
  end

  defp parse_tag_tree("</" <> rest, pos, entries, stack, counter) do
    {_, remaining} = consume_tag_body(rest)
    [_ | stack] = stack
    parse_tag_tree(remaining, pos, entries, stack, counter)
  end

  defp parse_tag_tree("<" <> rest, pos, entries, stack, counter) do
    {tag_body, remaining} = consume_tag_body(rest)
    tag_name = tag_body |> String.split(~r/[\s\/]/, parts: 2) |> hd()
    self_closing? = String.ends_with?(tag_body, "/")
    counter = counter + 1

    parent_pos = List.first(stack, nil)

    # Count how many children this parent already has
    child_idx =
      if parent_pos do
        entries
        |> Enum.count(fn {_, _, p, _} -> p == parent_pos end)
      else
        0
      end

    entry = {counter, tag_name, parent_pos, child_idx}

    if self_closing? or void_element?(tag_name) do
      parse_tag_tree(remaining, pos, [entry | entries], stack, counter)
    else
      parse_tag_tree(remaining, pos, [entry | entries], [counter | stack], counter)
    end
  end

  defp parse_tag_tree(<<_::utf8, rest::binary>>, pos, entries, stack, counter) do
    parse_tag_tree(rest, pos + 1, entries, stack, counter)
  end

  defp void_element?(tag) do
    tag in ~w(area base br col embed hr img input link meta param source track wbr)
  end

  defp find_nth_child_tag(tag_tree, parent_tag_pos, n) do
    tag_tree
    |> Enum.filter(fn {_, _, parent, _} -> parent == parent_tag_pos end)
    |> Enum.at(n)
    |> case do
      {tag_pos, _, _, _} -> tag_pos
      nil -> nil
    end
  end

  defp find_nth_sibling_tag(tag_tree, prev_tag_pos, n) do
    # Find the parent of prev, then find the sibling at offset n after prev
    case Enum.find(tag_tree, fn {pos, _, _, _} -> pos == prev_tag_pos end) do
      {_, _, parent_pos, child_idx} ->
        target_idx = child_idx + n

        tag_tree
        |> Enum.filter(fn {_, _, parent, _} -> parent == parent_pos end)
        |> Enum.at(target_idx)
        |> case do
          {tag_pos, _, _, _} -> tag_pos
          nil -> nil
        end

      nil ->
        nil
    end
  end

  defp resolve_template(returns, templates, etm_map) do
    returns
    |> Enum.map(fn element_id ->
      template_idx = Map.get(etm_map, element_id, element_id)
      Enum.at(templates, template_idx) || ""
    end)
    |> Enum.join()
  end

  defp build_static_dynamic(template_html, text_effects, props_by_element, html_effects, structural_ops, directive_ops, _templates, _etm_map, elem_to_tag) do
    # Phase 1: Inject prop markers into opening tags
    {marked_html, prop_specs} = inject_prop_markers(template_html, props_by_element, elem_to_tag)

    # Phase 1b: Inject directive markers (v-show, v-model)
    {marked_html, directive_specs} = inject_directive_markers(marked_html, directive_ops, elem_to_tag)

    # Phase 2: Inject structural markers into parent elements
    {marked_html, struct_specs} = inject_structural_markers(marked_html, structural_ops, elem_to_tag)

    # Phase 3: Unified split — directive specs go through the prop queue
    # since they appear in the same position (inside opening tags)
    unified_split(marked_html, text_effects, html_effects, prop_specs ++ directive_specs, struct_specs)
  end

  defp inject_directive_markers(html, [], _elem_to_tag), do: {html, []}

  defp inject_directive_markers(html, directive_ops, elem_to_tag) do
    Enum.reduce(directive_ops, {html, []}, fn dir, {h, specs} ->
      tag_pos = Map.get(elem_to_tag, dir.element, dir.element)
      expr = dir[:value]

      case dir.name do
        "vShow" ->
          keys = if expr, do: Expr.assign_keys(expr), else: :all
          spec = {:v_show, expr, keys}
          new_h = inject_attr_into_nth_tag(h, tag_pos, " style=\"#{@prop_marker}\"")
          {new_h, specs ++ [spec]}

        "model" ->
          keys = if expr, do: Expr.assign_keys(expr), else: :all
          spec = {:v_model, expr, keys}
          handler = "#{expr}_changed"
          new_h =
            h
            |> inject_attr_into_nth_tag(tag_pos, " value=\"#{@prop_marker}\"")
            |> inject_attr_into_nth_tag(tag_pos, " phx-change=\"#{handler}\"")
          {new_h, specs ++ [spec]}

        _ ->
          {h, specs}
      end
    end)
  end

  defp inject_structural_markers(html, [], _elem_to_tag), do: {html, []}

  defp inject_structural_markers(html, structural_ops, elem_to_tag) do
    Enum.reduce(structural_ops, {html, []}, fn op, {h, specs} ->
      parent_id = op.parent

      spec =
        case op.kind do
          :if_node -> {:if_node, op, Expr.assign_keys(op.condition)}
          :for_node -> {:for_node, op, Expr.assign_keys(op.source)}
          :create_component -> {:create_component, op, component_assign_keys(op)}
        end

      new_h =
        if parent_id == nil do
          h <> @struct_marker
        else
          tag_pos = Map.get(elem_to_tag, parent_id, parent_id)
          inject_content_into_nth_tag(h, tag_pos, @struct_marker)
        end

      {new_h, specs ++ [spec]}
    end)
  end

  # Injects content before the closing tag of the nth opening tag.
  # For <div><span>x</span></div> with target 0 and content "M":
  # → <div><span>x</span>M</div>
  defp inject_content_into_nth_tag(html, target_n, content) do
    tags = parse_tag_tree(html)
    {_, tag_name, _, _} = Enum.at(tags, target_n)

    # Find the byte position of the target opening tag
    open_byte_pos = find_nth_open_tag_byte_pos(html, target_n)

    # Skip past the opening tag's ">"
    after_open = skip_past_gt(html, open_byte_pos)

    # From there, find the matching closing tag (tracking nesting)
    close_pos = find_matching_close(html, after_open, tag_name, 0)

    if close_pos do
      {before, rest} = String.split_at(html, close_pos)
      before <> content <> rest
    else
      # Self-closing or void — inject right after the opening tag
      {before, rest} = String.split_at(html, after_open)
      before <> content <> rest
    end
  end

  defp find_nth_open_tag_byte_pos(html, n) do
    find_nth_open_tag_byte_pos(html, n, 0, 0)
  end

  defp find_nth_open_tag_byte_pos(<<"</", rest::binary>>, n, pos, count) do
    {_, remaining} = consume_tag_body(rest)
    skip = byte_size(rest) - byte_size(remaining) + 2
    find_nth_open_tag_byte_pos(remaining, n, pos + skip, count)
  end

  defp find_nth_open_tag_byte_pos(<<"<", rest::binary>>, n, pos, count) do
    if count == n do
      pos
    else
      {tag_body, remaining} = consume_tag_body(rest)
      skip = byte_size(tag_body) + 2
      find_nth_open_tag_byte_pos(remaining, n, pos + skip, count + 1)
    end
  end

  defp find_nth_open_tag_byte_pos(<<_::utf8, rest::binary>>, n, pos, count) do
    find_nth_open_tag_byte_pos(rest, n, pos + 1, count)
  end

  defp find_nth_open_tag_byte_pos("", _n, pos, _count), do: pos

  defp skip_past_gt(html, pos) do
    case :binary.at(html, pos) do
      ?> -> pos + 1
      _ -> skip_past_gt(html, pos + 1)
    end
  rescue
    _ -> pos
  end

  defp find_matching_close(html, pos, tag_name, depth) do
    remaining = binary_part(html, pos, byte_size(html) - pos)
    close_tag = "</#{tag_name}>"
    open_prefix = "<#{tag_name}"

    cond do
      remaining == "" ->
        nil

      String.starts_with?(remaining, close_tag) ->
        if depth == 0, do: pos, else: find_matching_close(html, pos + byte_size(close_tag), tag_name, depth - 1)

      String.starts_with?(remaining, open_prefix) ->
        next_char_pos = byte_size(open_prefix)
        next_char = if next_char_pos < byte_size(remaining), do: :binary.at(remaining, next_char_pos), else: nil

        if next_char in [?\s, ?>, ?/] do
          {tag_body, _} = consume_tag_body(binary_part(remaining, 1, byte_size(remaining) - 1))
          tag_end = pos + 1 + byte_size(tag_body) + 1

          if String.ends_with?(tag_body, "/") or void_element?(tag_name) do
            find_matching_close(html, tag_end, tag_name, depth)
          else
            find_matching_close(html, tag_end, tag_name, depth + 1)
          end
        else
          find_matching_close(html, pos + 1, tag_name, depth)
        end

      :binary.at(remaining, 0) == ?< ->
        {tag_body, _} = consume_tag_body(binary_part(remaining, 1, byte_size(remaining) - 1))
        find_matching_close(html, pos + 1 + byte_size(tag_body) + 1, tag_name, depth)

      true ->
        find_matching_close(html, pos + 1, tag_name, depth)
    end
  end

  defp inject_prop_markers(html, props_by_element, _elem_to_tag) when map_size(props_by_element) == 0 do
    {html, []}
  end

  defp inject_prop_markers(html, props_by_element, elem_to_tag) do
    sorted_elements = props_by_element |> Map.keys() |> Enum.sort()

    Enum.reduce(sorted_elements, {html, []}, fn element_id, {h, specs} ->
      tag_pos = Map.get(elem_to_tag, element_id, element_id)
      props = Map.fetch!(props_by_element, element_id)

      Enum.reduce(props, {h, specs}, fn prop, {h2, specs2} ->
        attr_name = extract_key(prop.value.key)
        keys = Expr.values_assign_keys(prop.value.values)
        spec = {:prop, prop.value.values, keys}

        new_h = inject_attr_into_nth_tag(h2, tag_pos, " #{attr_name}=\"#{@prop_marker}\"")
        {new_h, specs2 ++ [spec]}
      end)
    end)
  end

  defp inject_attr_into_nth_tag(html, target_n, injection) do
    do_inject_attr(html, target_n, injection, 0, [])
  end

  defp do_inject_attr("", _target, _injection, _count, acc) do
    acc |> Enum.reverse() |> IO.iodata_to_binary()
  end

  defp do_inject_attr("</" <> rest, target, injection, count, acc) do
    {tag_body, remaining} = consume_tag_body(rest)
    do_inject_attr(remaining, target, injection, count, ["</" <> tag_body <> ">" | acc])
  end

  defp do_inject_attr("<" <> rest, target, injection, count, acc) do
    {tag_body, remaining} = consume_tag_body(rest)

    if count == target do
      IO.iodata_to_binary(Enum.reverse(["<" <> tag_body <> injection <> ">" | acc])) <> remaining
    else
      do_inject_attr(remaining, target, injection, count + 1, ["<" <> tag_body <> ">" | acc])
    end
  end

  defp do_inject_attr(<<c::utf8, rest::binary>>, target, injection, count, acc) do
    do_inject_attr(rest, target, injection, count, [<<c::utf8>> | acc])
  end

  defp consume_tag_body(str), do: consume_tag_body(str, [])
  defp consume_tag_body(">" <> rest, acc), do: {acc |> Enum.reverse() |> IO.iodata_to_binary(), rest}
  defp consume_tag_body(<<c::utf8, rest::binary>>, acc), do: consume_tag_body(rest, [<<c::utf8>> | acc])
  defp consume_tag_body("", acc), do: {acc |> Enum.reverse() |> IO.iodata_to_binary(), ""}

  defp unified_split(html, text_effects, html_effects, prop_specs, struct_specs) do
    text_queue = :queue.from_list(text_effects ++ html_effects)
    prop_queue = :queue.from_list(prop_specs)
    struct_queue = :queue.from_list(struct_specs)

    escaped_prop = Regex.escape(@prop_marker)
    escaped_struct = Regex.escape(@struct_marker)
    pattern = Regex.compile!("(?<=>)( )(?=<)|#{escaped_prop}|#{escaped_struct}")

    segments = Regex.split(pattern, html, include_captures: true)

    {statics, specs, _tq, _pq, _sq} =
      Enum.reduce(segments, {[""], [], text_queue, prop_queue, struct_queue}, fn
        " ", {[prev | rest], specs, tq, pq, sq} ->
          case :queue.out(tq) do
            {{:value, effect}, tq2} ->
              keys = effect_keys(effect)
              spec = {effect.kind, effect.values, keys}
              {["", prev | rest], [spec | specs], tq2, pq, sq}

            {:empty, tq2} ->
              {[prev <> " " | rest], specs, tq2, pq, sq}
          end

        @prop_marker, {statics, specs, tq, pq, sq} ->
          case :queue.out(pq) do
            {{:value, spec}, pq2} ->
              {["" | statics], [spec | specs], tq, pq2, sq}

            {:empty, pq2} ->
              {statics, specs, tq, pq2, sq}
          end

        @struct_marker, {statics, specs, tq, pq, sq} ->
          case :queue.out(sq) do
            {{:value, spec}, sq2} ->
              {["" | statics], [spec | specs], tq, pq, sq2}

            {:empty, sq2} ->
              {statics, specs, tq, pq, sq2}
          end

        text, {[prev | rest], specs, tq, pq, sq} ->
          {[prev <> text | rest], specs, tq, pq, sq}
      end)

    {Enum.reverse(statics), Enum.reverse(specs)}
  end

  defp effect_keys(%{kind: :set_text, values: values}), do: Expr.values_assign_keys(values)
  defp effect_keys(%{kind: :set_html, value: value}), do: Expr.assign_keys(value)
  defp effect_keys(%{kind: :set_html, values: values}), do: Expr.values_assign_keys(values)
  defp effect_keys(_), do: :all

  defp extract_key({:static_, name}), do: name
  defp extract_key(name) when is_binary(name), do: name

  defp spec_changed?({_kind, _data, :all}, _changed), do: true

  defp spec_changed?({_kind, _data, keys}, changed) when is_list(keys) do
    Enum.any?(keys, &Map.has_key?(changed, &1))
  end

  defp spec_changed?(_, _), do: true

  defp eval_spec({:set_text, values, _keys}, assigns, _templates, _etm_map) do
    Expr.eval_values(values, assigns)
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end

  defp eval_spec({:set_html, values, _keys}, assigns, _templates, _etm_map) do
    Expr.eval_values(values, assigns)
  end

  defp eval_spec({:prop, values, _keys}, assigns, _templates, _etm_map) do
    Expr.eval_values(values, assigns)
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end

  defp eval_spec({:v_show, expr, _keys}, assigns, _templates, _etm_map) do
    if Expr.eval(expr, assigns) do
      ""
    else
      "display: none"
    end
  end

  defp eval_spec({:v_model, expr, _keys}, assigns, _templates, _etm_map) do
    Expr.eval(expr, assigns)
    |> to_string()
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end

  defp eval_spec({:if_node, op, _keys}, assigns, templates, etm_map) do
    condition_value = Expr.eval(op.condition, assigns)

    if condition_value do
      block_to_rendered(op.positive, templates, etm_map, assigns)
    else
      case op.negative do
        nil ->
          ""

        %{kind: :if_node} = nested_if ->
          eval_spec({:if_node, nested_if, Expr.assign_keys(nested_if.condition)}, assigns, templates, etm_map)

        %{returns: _, operations: _, effects: _} = block ->
          block_to_rendered(block, templates, etm_map, assigns)
      end
    end
  end

  defp eval_spec({:for_node, op, _keys}, assigns, templates, etm_map) do
    items = Expr.eval(op.source, assigns) || []
    value_name = op.value
    render_block = op.render
    key_prop = op[:key_prop]

    # Render the block once to get the correct static parts
    # (which include prop markers, structural markers, etc.)
    dummy_assigns = build_item_assigns(assigns, value_name, %{})
    prototype = block_to_rendered(render_block, templates, etm_map, dummy_assigns)
    static_parts = prototype.static
    fingerprint = prototype.fingerprint

    entries =
      Enum.map(items, fn item ->
        item_assigns = build_item_assigns(assigns, value_name, item)

        key =
          if key_prop do
            Expr.eval(key_prop, item_assigns) |> to_string()
          end

        render_fn = fn _vars_changed, _track_changes? ->
          rendered = block_to_rendered(render_block, templates, etm_map, item_assigns)
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

  defp eval_spec({:create_component, op, _keys}, assigns, _templates, _etm_map) do
    tag = op.tag
    props = op[:props] || []

    # Build assigns for the component from its props
    comp_assigns =
      Enum.reduce(props, %{}, fn prop, acc ->
        key_name = extract_key(prop.key)
        value = Expr.eval_values(prop.values, assigns)
        Map.put(acc, String.to_atom(key_name), value)
      end)

    # Look up the component as a function in assigns or skip
    case Map.get(assigns, :__components__, %{}) |> Map.get(tag) do
      nil ->
        case Map.get(assigns, :__components__, %{}) |> Map.get(String.to_atom(tag)) do
          nil -> ""
          component_fn -> component_fn.(comp_assigns)
        end

      component_fn ->
        component_fn.(comp_assigns)
    end
  end

  defp build_item_assigns(assigns, value_name, item) do
    assigns
    |> Map.put(value_name, item)
    |> Map.put(String.to_atom(value_name), item)
  end

  defp component_assign_keys(op) do
    (op[:props] || [])
    |> Enum.flat_map(fn prop -> Expr.values_assign_keys(prop.values) end)
    |> Enum.uniq()
  end

  defp compute_fingerprint(static, block) do
    <<fingerprint::8*16>> =
      [block | static]
      |> :erlang.term_to_binary()
      |> :erlang.md5()

    fingerprint
  end
end
