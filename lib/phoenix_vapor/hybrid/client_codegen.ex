defmodule PhoenixVapor.Hybrid.ClientCodegen do
  @moduledoc """
  Generates client-side JavaScript for hybrid components.

  Takes Vize's compiled SFC output and:
  1. Replaces server action bodies with optimistic prop updates and a `pushEvent`
  2. Exports `__mount/3`, which mounts one instance with its own props and bridge
  """

  alias PhoenixVapor.Hybrid.Classifier

  import PhoenixVapor.JS, only: [patch: 3]

  @doc """
  Generate the client JS module for a hybrid component.

  Takes the raw SFC source and classification, produces a self-contained
  JS module that can hydrate server-rendered HTML and manage client reactivity.

  ## Options

    * `:source_dir` and `:output_dir` — when the module is written to a
      different directory than the `.vue` file, relative imports such as
      `./ui/Button.vue` are rewritten to resolve from `:output_dir`.
  """
  @spec generate(String.t(), Classifier.classification(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def generate(sfc_source, classification, opts \\ []) do
    sfc_source = strip_elixir_block(sfc_source)

    case Vize.compile_sfc(sfc_source) do
      {:ok, result} ->
        js = transform(result.code, classification, opts)
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
  @spec transform(String.t(), Classifier.classification(), keyword()) :: String.t()
  def transform(vize_code, classification, opts \\ []) do
    {:ok, ast} = OXC.parse(vize_code, "module.js")

    patches =
      server_action_patches(ast, vize_code, classification) ++
        setup_patches(ast) ++ default_export_patches(ast) ++ import_patches(ast, opts)

    preamble(classification) <> "\n" <> OXC.patch_string(vize_code, patches) <> exports()
  end

  defp import_patches(ast, opts) do
    case {opts[:source_dir], opts[:output_dir]} do
      {from, to} when is_binary(from) and is_binary(to) and from != to ->
        ast
        |> OXC.collect(fn
          %{type: type, source: %{type: :literal, value: "." <> _ = spec} = source}
          when type in [
                 :import_declaration,
                 :export_all_declaration,
                 :export_named_declaration,
                 :import_expression
               ] ->
            {:keep, {source, spec}}

          _ ->
            :skip
        end)
        |> Enum.map(fn {source, spec} ->
          rebased =
            from
            |> Path.join(spec)
            |> Path.expand()
            |> Path.relative_to(Path.expand(to), force: true)

          rebased = if String.starts_with?(rebased, "."), do: rebased, else: "./" <> rebased
          patch(source.start, source.end, Jason.encode!(rebased))
        end)

      _ ->
        []
    end
  end

  defp preamble(classification) do
    """
    import { createApp as __createApp, h as __h, inject as __inject, reactive as __reactive } from 'vue';

    export function __getClientState() {
      return #{Jason.encode!(client_refs(classification))};
    }
    """
  end

  # Each mount gets its own props and bridge, provided to the component's
  # setup as `__pv`, so a page can mount the same component several times.
  defp exports do
    """

    export { __component as default };

    export function __mount(el, bridge, props = {}) {
      const state = __reactive({ ...props });
      // Rendering through h() reads the props inside the root render effect,
      // so applyProps re-renders. createApp(component, props) would copy them.
      const app = __createApp({ render: () => __h(__component, state) });
      app.provide("__pv", { bridge, props: state });
      app.mount(el);

      return {
        applyProps(next) {
          for (const key of Object.keys(state)) {
            if (!(key in next)) delete state[key];
          }
          Object.assign(state, next);
        },
        unmount() {
          app.unmount();
        }
      };
    }
    """
  end

  defp setup_patches(ast) do
    ast
    |> OXC.collect(fn
      %{type: :export_default_declaration, declaration: %{type: :object_expression} = component} ->
        patches =
          for %{type: :property, key: %{name: "setup"}, value: %{body: %{start: start}}} <-
                component.properties,
              do: patch(start + 1, start + 1, ~s|\n  const __pv = __inject("__pv");|)

        {:keep, patches}

      _ ->
        :skip
    end)
    |> List.flatten()
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
      "__pv.bridge.pushEvent(#{Jason.encode!(name)}, #{event_params(body, params, code, classification)});"

    statements = Enum.flat_map(body.body, &optimistic_update(&1, code, classification)) ++ [push]
    change = IO.iodata_to_binary([Enum.map(statements, &["\n  ", &1]), "\n"])

    patch(body.start + 1, body.end - 1, change)
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
      prop -> ["__pv.props[#{Jason.encode!(prop)}] = #{slice(code, right)};"]
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
        {:keep, patch(s, ds, "const __component = ")}

      _ ->
        :skip
    end)
  end

  defp slice(code, %{start: s, end: e}), do: binary_part(code, s, e - s)

  # Vize would copy a `<script lang="elixir">` block into the module, so drop
  # the block, tags included, using the span the SFC parser reports.
  defp strip_elixir_block(sfc_source) do
    case Vize.parse_sfc(sfc_source) do
      {:ok, %{script: %{lang: "elixir", loc: %{tag_start: s, tag_end: e}}}} ->
        binary_part(sfc_source, 0, s) <> binary_part(sfc_source, e, byte_size(sfc_source) - e)

      _ ->
        sfc_source
    end
  end
end
