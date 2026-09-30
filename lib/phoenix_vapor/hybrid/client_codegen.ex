defmodule PhoenixVapor.Hybrid.ClientCodegen do
  @moduledoc """
  Generates client-side JavaScript for hybrid components.

  Takes Vize's compiled SFC output and:
  1. Replaces server action bodies with optimistic prop updates and a `pushEvent`
  2. Adds the bridge exports (`__mount`, `__applyProps`, `__setBridge`, ...)
  """

  alias PhoenixVapor.Hybrid.Classifier

  @doc """
  Generate the client JS module for a hybrid component.

  Takes the raw SFC source and classification, produces a self-contained
  JS module that can hydrate server-rendered HTML and manage client reactivity.
  """
  @spec generate(String.t(), Classifier.classification()) :: {:ok, String.t()} | {:error, term()}
  def generate(sfc_source, classification) do
    sfc_source = strip_elixir_block(sfc_source)

    case Vize.compile_sfc(sfc_source) do
      {:ok, result} ->
        js = transform(result.code, classification)
        {:ok, js}

      {:error, errors} ->
        {:error, errors}
    end
  end

  @doc """
  Transform Vize's compiled SFC output for hybrid mode.

  Replaces server action bodies with optimistic prop updates followed by a
  `pushEvent`, and wraps the component with the bridge exports.
  """
  @spec transform(String.t(), Classifier.classification()) :: String.t()
  def transform(vize_code, classification) do
    {:ok, ast} = OXC.parse(vize_code, "module.js")
    patches = server_action_patches(ast, vize_code, classification) ++ default_export_patches(ast)

    preamble(classification) <> "\n" <> OXC.patch_string(vize_code, patches) <> exports()
  end

  defp preamble(classification) do
    """
    import { createApp as __createApp, h as __h, reactive as __reactive } from 'vue';
    let __bridge = null;
    const __propsState = __reactive({});

    export function __applyProps(props) {
      for (const key of Object.keys(__propsState)) {
        if (!(key in props)) delete __propsState[key];
      }
      Object.assign(__propsState, props);
    }

    export function __setBridge(bridge) {
      __bridge = bridge;
    }

    export function __getClientState() {
      return #{Jason.encode!(client_refs(classification))};
    }
    """
  end

  defp exports do
    """

    export { __component as default };

    let __app = null;

    export function __mount(el, bridge) {
      if (bridge) __bridge = bridge;
      // Rendering through h() reads __propsState inside the root render effect,
      // so later __applyProps calls re-render. createApp(component, props) would
      // copy the props once.
      __app = __createApp({ render: () => __h(__component, __propsState) });
      __app.mount(el);
    }

    export function __unmount() {
      if (__app) { __app.unmount(); __app = null; }
    }
    """
  end

  defp client_refs(classification) do
    for {name, {:client_ref, _}} <- classification.bindings, do: name
  end

  defp client_values(classification) do
    for {name, kind} <- classification.bindings,
        match?({:client_ref, _}, kind) or kind == :client_computed or
          match?({:mixed_computed, _, _}, kind),
        into: MapSet.new(),
        do: name
  end

  defp server_action_patches(ast, code, classification) do
    actions =
      for {name, {:server_action, _body}} <- classification.handlers, into: MapSet.new(), do: name

    OXC.collect(ast, fn
      %{type: :function_declaration, id: %{name: name}} = fun ->
        if MapSet.member?(actions, name) do
          {:keep, server_action_patch(fun, code, classification)}
        else
          :skip
        end

      _ ->
        :skip
    end)
  end

  defp server_action_patch(%{id: %{name: name}, params: params, body: body}, code, classification) do
    push =
      "__bridge.pushEvent(#{Jason.encode!(name)}, #{event_params(body, params, code, classification)});"

    statements = Enum.flat_map(body.body, &optimistic_update(&1, code, classification)) ++ [push]
    change = IO.iodata_to_binary([Enum.map(statements, &["\n  ", &1]), "\n"])

    %{start: body.start + 1, end: body.end - 1, change: change}
  end

  # `prop = expr` and `props.prop = expr` apply locally before the server confirms.
  defp optimistic_update(
         %{
           type: :expression_statement,
           expression: %{type: :assignment_expression, operator: "=", left: left, right: right}
         },
         code,
         classification
       ) do
    case assigned_prop(left, classification) do
      nil -> []
      prop -> ["__propsState[#{Jason.encode!(prop)}] = #{slice(code, right)};"]
    end
  end

  defp optimistic_update(_statement, _code, _classification), do: []

  defp assigned_prop(%{type: :identifier, name: name}, classification) do
    if name in all_props(classification), do: name
  end

  defp assigned_prop(
         %{
           type: :member_expression,
           computed: false,
           object: %{type: :identifier, name: "props"},
           property: %{name: name}
         },
         classification
       ) do
    if name in all_props(classification), do: name
  end

  defp assigned_prop(_left, _classification), do: nil

  defp all_props(classification),
    do: classification.client_props ++ classification.server_only_props

  # Sends the action's arguments and the current value of each client ref or
  # computed it reads.
  defp event_params(body, params, code, classification) do
    param_names =
      for %{type: :identifier, name: name} <- params, do: name

    values = client_values(classification)

    pairs =
      code
      |> slice(body)
      |> Classifier.free_variables()
      |> Enum.flat_map(fn name ->
        cond do
          name in param_names -> ["#{Jason.encode!(name)}: #{name}"]
          MapSet.member?(values, name) -> ["#{Jason.encode!(name)}: #{name}.value"]
          true -> []
        end
      end)

    IO.iodata_to_binary(["{", Enum.intersperse(pairs, ", "), "}"])
  end

  defp default_export_patches(ast) do
    OXC.collect(ast, fn
      %{type: :export_default_declaration, start: s, declaration: %{start: ds}} ->
        {:keep, %{start: s, end: ds, change: "const __component = "}}

      _ ->
        :skip
    end)
  end

  defp slice(code, %{start: s, end: e}), do: binary_part(code, s, e - s)

  defp strip_elixir_block(sfc_source) do
    case Vize.parse_sfc(sfc_source) do
      {:ok, %{script: %{lang: "elixir", loc: %{start: s, end: e}}}} ->
        tag_start = find_script_open_tag(sfc_source, s)
        suffix = binary_part(sfc_source, e, byte_size(sfc_source) - e)

        close_end = find_close_script_end(suffix)
        remaining = binary_part(suffix, close_end, byte_size(suffix) - close_end)

        binary_part(sfc_source, 0, tag_start) <> remaining

      _ ->
        sfc_source
    end
  end

  defp find_script_open_tag(source, content_start) do
    prefix = binary_part(source, 0, content_start)

    case :binary.match(prefix, "<script") do
      {pos, _} -> pos
      :nomatch -> content_start
    end
  end

  defp find_close_script_end(suffix) do
    case :binary.match(suffix, "</script>") do
      {pos, len} -> pos + len
      :nomatch -> 0
    end
  end
end
