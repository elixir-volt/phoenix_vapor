defmodule PhoenixVapor.Hybrid.ClientCodegen do
  @moduledoc """
  Generates client-side JavaScript for hybrid components.

  Takes the Vize Vue Vapor SFC compilation output and transforms it:
  1. Replaces `__props` with a bridge-controlled reactive source
  2. Replaces server action bodies with optimistic update + pushEvent stubs
  3. Adds bridge initialization and props application exports
  """

  alias PhoenixVapor.Hybrid.Classifier

  @doc """
  Generate the client JS module for a hybrid component.

  Takes the raw SFC source and classification, produces a self-contained
  JS module that can hydrate server-rendered HTML and manage client reactivity.
  """
  @spec generate(String.t(), Classifier.classification()) :: {:ok, String.t()} | {:error, term()}
  def generate(sfc_source, classification) do
    case Vize.compile_sfc(sfc_source, vapor: true) do
      {:ok, result} ->
        js = transform(result.code, classification)
        {:ok, js}

      {:error, errors} ->
        {:error, errors}
    end
  end

  @doc """
  Transform Vize's Vue Vapor output for hybrid mode.

  Performs AST-based rewrites:
  - Wraps `__props` access in a reactive bridge
  - Replaces server action function bodies
  - Adds bridge exports
  """
  @spec transform(String.t(), Classifier.classification()) :: String.t()
  def transform(vize_code, classification) do
    server_actions = extract_server_actions(classification)

    vize_code
    |> inject_bridge_preamble(classification)
    |> rewrite_props_source()
    |> rewrite_server_actions(server_actions, classification)
    |> inject_bridge_exports()
  end

  defp inject_bridge_preamble(code, classification) do
    client_refs =
      classification.bindings
      |> Enum.filter(fn {_, kind} -> match?({:client_ref, _}, kind) end)
      |> Enum.map(fn {name, _} -> name end)
      |> Enum.sort()

    preamble = """
    import { shallowRef, triggerRef } from 'vue';
    const __serverProps = { value: {} };
    let __bridge = null;

    export function __applyProps(props) {
      __serverProps.value = props;
    }

    export function __setBridge(bridge) {
      __bridge = bridge;
    }

    export function __getClientState() {
      return #{client_state_keys_json(client_refs)};
    }
    """

    preamble <> "\n" <> code
  end

  defp client_state_keys_json(refs) do
    pairs = Enum.map_join(refs, ", ", fn name -> ~s("#{name}") end)
    "[#{pairs}]"
  end

  # Workaround: Vue Vapor 3.6.0-alpha does not forward component props
  # to setup(__props) via createVaporApp(). Replace `const props = __props`
  # with direct access to our reactive bridge object.
  # Remove when Vue Vapor stabilizes prop forwarding.
  defp rewrite_props_source(code) do
    code
    |> String.replace("const props = __props", "const props = __serverProps.value")
    |> String.replace(
      ~r/setup\(__props,\s*\{/,
      "setup(__pvOriginalProps, {"
    )
    |> String.replace(
      ~r/return __vaporRender\(__ctx,\s*__props,/,
      "return __vaporRender(__ctx, __serverProps.value,"
    )
  end

  defp rewrite_server_actions(code, server_actions, classification) do
    Enum.reduce(server_actions, code, fn {name, original_body}, acc ->
      rewrite_single_action(acc, name, original_body, classification)
    end)
  end

  defp rewrite_single_action(code, name, original_body, classification) do
    optimistic_code = generate_optimistic_update(name, original_body, classification)
    params = generate_params_extraction(original_body, classification)
    push_code = ~s|__bridge.pushEvent("#{name}", #{params})|
    new_body = "#{optimistic_code}\n    #{push_code}"

    replace_function_body(code, name, new_body)
  end

  defp generate_optimistic_update(_name, body, classification) do
    # Parse the body to find assignments to server props
    case OXC.parse(body, "fn.js") do
      {:ok, ast} ->
        assignments = collect_prop_assignments(ast, classification)

        Enum.map_join(assignments, "\n    ", fn {prop, expr} ->
          "Object.assign(__serverProps.value, { #{prop}: #{expr} });\n    triggerRef(__serverProps);"
        end)

      _ ->
        ""
    end
  end

  defp collect_prop_assignments(ast, classification) do
    prop_set = MapSet.new(classification.client_props ++ classification.server_only_props)

    OXC.collect(ast, fn
      %{type: :expression_statement,
        expression: %{type: :assignment_expression, operator: "=",
                      left: %{type: :identifier, name: name}}} = stmt ->
        if MapSet.member?(prop_set, name) do
          # Get the RHS source text — we reconstruct it from the expression
          {:keep, {name, reconstruct_rhs(stmt.expression.right)}}
        else
          :skip
        end

      _ ->
        :skip
    end)
  end

  defp reconstruct_rhs(%{type: :call_expression, callee: callee, arguments: args}) do
    callee_str = reconstruct_rhs(callee)
    args_str = Enum.map_join(args, ", ", &reconstruct_rhs/1)
    "#{callee_str}(#{args_str})"
  end

  defp reconstruct_rhs(%{type: :member_expression, object: obj, property: prop, computed: false}) do
    "#{reconstruct_rhs(obj)}.#{prop.name}"
  end

  defp reconstruct_rhs(%{type: :member_expression, object: obj, property: prop, computed: true}) do
    "#{reconstruct_rhs(obj)}[#{reconstruct_rhs(prop)}]"
  end

  defp reconstruct_rhs(%{type: :identifier, name: name}), do: name

  defp reconstruct_rhs(%{type: :arrow_function_expression, params: params, body: body}) do
    params_str = Enum.map_join(params, ", ", &reconstruct_rhs/1)
    body_str = reconstruct_rhs(body)
    "(#{params_str}) => #{body_str}"
  end

  defp reconstruct_rhs(%{type: :binary_expression, left: l, operator: op, right: r}) do
    "#{reconstruct_rhs(l)} #{op} #{reconstruct_rhs(r)}"
  end

  defp reconstruct_rhs(%{type: :literal, raw: raw}), do: raw
  defp reconstruct_rhs(%{type: :literal, value: value}) when is_binary(value), do: ~s("#{value}")
  defp reconstruct_rhs(%{type: :literal, value: value}), do: to_string(value)

  defp reconstruct_rhs(%{type: :object_expression, properties: props}) do
    pairs = Enum.map_join(props, ", ", fn p ->
      key = reconstruct_rhs(p.key)
      val = reconstruct_rhs(p.value)
      if p[:shorthand], do: key, else: "#{key}: #{val}"
    end)
    "{ #{pairs} }"
  end

  defp reconstruct_rhs(%{type: :spread_element, argument: arg}) do
    "...#{reconstruct_rhs(arg)}"
  end

  defp reconstruct_rhs(%{type: :array_expression, elements: elems}) do
    "[#{Enum.map_join(elems, ", ", &reconstruct_rhs/1)}]"
  end

  defp reconstruct_rhs(_node), do: "undefined"

  defp generate_params_extraction(body, classification) do
    prop_names = MapSet.new(classification.client_props ++ classification.server_only_props)

    params =
      body
      |> Classifier.free_variables()
      |> Enum.reject(&MapSet.member?(prop_names, &1))

    if params == [] do
      "{}"
    else
      pairs = Enum.map_join(params, ", ", fn name -> "#{name}: #{name}" end)
      "{ #{pairs} }"
    end
  end

  defp replace_function_body(code, fn_name, new_body) do
    # The function lives inside setup() which is inside an object expression.
    # OXC may fail to parse the full hybrid output (it has module-level statements
    # mixed with export default). Use a targeted approach: find the function
    # declaration pattern and replace its body.
    #
    # Strategy: parse the setup body content in isolation to find the function span,
    # then map the offsets back to the full code.
    case find_function_in_code(code, fn_name) do
      {body_start, body_end} ->
        OXC.patch_string(code, [
          %{start: body_start + 1, end: body_end - 1, change: " #{new_body} "}
        ])

      nil ->
        code
    end
  end

  defp find_function_in_code(code, target_name) do
    # Find `function <name>(` pattern and then locate its body braces
    pattern = "function #{target_name}("

    case :binary.match(code, pattern) do
      {start, _len} ->
        # Find the opening brace of the function body
        rest = binary_part(code, start, byte_size(code) - start)
        find_balanced_braces(rest, start)

      :nomatch ->
        nil
    end
  end

  defp find_balanced_braces(str, base_offset) do
    case find_char(str, ?{, 0) do
      nil ->
        nil

      open_pos ->
        after_open = binary_part(str, open_pos + 1, byte_size(str) - open_pos - 1)
        close_relative = find_matching_close(after_open, 0, 1)

        if close_relative do
          {base_offset + open_pos, base_offset + open_pos + 1 + close_relative}
        end
    end
  end

  defp find_char(<<c, _rest::binary>>, c, pos), do: pos
  defp find_char(<<_, rest::binary>>, c, pos), do: find_char(rest, c, pos + 1)
  defp find_char(<<>>, _c, _pos), do: nil

  defp find_matching_close(<<>>, _pos, _depth), do: nil
  defp find_matching_close(_, _pos, depth) when depth < 0, do: nil

  defp find_matching_close(<<c, rest::binary>>, pos, depth) do
    cond do
      c == ?} and depth == 1 -> pos
      c == ?} -> find_matching_close(rest, pos + 1, depth - 1)
      c == ?{ -> find_matching_close(rest, pos + 1, depth + 1)
      c == ?\" -> skip_string(rest, pos + 1, ?\", depth)
      c == ?' -> skip_string(rest, pos + 1, ?', depth)
      c == ?` -> skip_template_literal(rest, pos + 1, depth)
      true -> find_matching_close(rest, pos + 1, depth)
    end
  end

  defp skip_string(<<>>, _pos, _quote, _depth), do: nil
  defp skip_string(<<?\\, _, rest::binary>>, pos, quote, depth), do: skip_string(rest, pos + 2, quote, depth)
  defp skip_string(<<c, rest::binary>>, pos, c, depth), do: find_matching_close(rest, pos + 1, depth)
  defp skip_string(<<_, rest::binary>>, pos, quote, depth), do: skip_string(rest, pos + 1, quote, depth)

  defp skip_template_literal(<<>>, _pos, _depth), do: nil
  defp skip_template_literal(<<?\\, _, rest::binary>>, pos, depth), do: skip_template_literal(rest, pos + 2, depth)
  defp skip_template_literal(<<?`, rest::binary>>, pos, depth), do: find_matching_close(rest, pos + 1, depth)
  defp skip_template_literal(<<_, rest::binary>>, pos, depth), do: skip_template_literal(rest, pos + 1, depth)

  defp inject_bridge_exports(code) do
    # Replace `export default` with a local binding so __mount can reference it
    code =
      String.replace(
        code,
        ~r/export default\s+\/\*@__PURE__\*\/\s*/,
        "const __vaporComponent = /*@__PURE__*/"
      )

    code <>
      """

      export default __vaporComponent;

      export function __mount(el, bridge) {
        __bridge = bridge;
        const setup = __vaporComponent.setup;
        if (!setup) return;
        const result = setup(
          __serverProps.value,
          { emit: () => {}, attrs: {}, slots: {} }
        );
        if (result instanceof Node) el.appendChild(result);
        else if (Array.isArray(result)) result.forEach(n => { if (n instanceof Node) el.appendChild(n); });
      }
      """
  end

  defp extract_server_actions(classification) do
    classification.handlers
    |> Enum.filter(fn {_, kind} -> match?({:server_action, _}, kind) end)
    |> Enum.map(fn {name, {:server_action, body}} -> {name, body} end)
  end
end
