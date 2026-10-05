defmodule PhoenixVapor.Hybrid.ClientCodegen do
  @moduledoc false

  # Generates client-side JavaScript for hybrid components.
  #
  # Takes Vize's compiled SFC output and:
  # 1. Sends each server action to the server through the bridge after its body runs
  # 2. Exports `__mount/3`, which mounts one instance with its own props and bridge,
  # and applies each model's `update:` event to its props

  alias PhoenixVapor.Hybrid.Classifier

  import PhoenixVapor.JS, only: [patch: 3]

  @doc """
  Generate the client JS module for a hybrid component.

  Takes the raw SFC source and classification, produces a self-contained
  JS module that can hydrate server-rendered HTML and manage client reactivity.

  ## Options

    * `:record` — the client state a session replay needs, which setup
      registers with the bridge; by default, the refs
    * `:source_dir` and `:output_dir` — when the module is written to a
      different directory than the `.vue` file, relative imports such as
      `./ui/Button.vue` are rewritten to resolve from `:output_dir`.
  """
  @spec generate(String.t(), Classifier.classification(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def generate(sfc_source, classification, opts \\ []) do
    sfc_source = PhoenixVapor.Compiler.SFC.without_elixir_block(sfc_source)

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

  Sends each server action to the server through the bridge once its body
  has run, and wraps the component with the bridge exports.
  """
  @spec transform(String.t(), Classifier.classification(), keyword()) :: String.t()
  def transform(vize_code, classification, opts \\ []) do
    {:ok, ast} = OXC.parse(vize_code, "module.js")

    patches =
      server_action_patches(ast, vize_code, classification) ++
        setup_patches(ast, Keyword.get_lazy(opts, :record, fn -> client_refs(classification) end)) ++
        default_export_patches(ast) ++ import_patches(ast, opts)

    preamble(classification) <>
      "\n" <> OXC.patch_string(vize_code, patches) <> exports(classification)
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
    import { createApp as __createApp, h as __h, inject as __inject, reactive as __reactive, unref as __unref, watch as __watch } from 'vue';

    export function __getClientState() {
      return #{Jason.encode!(client_refs(classification))};
    }
    """
  end

  # Each mount gets its own props and bridge, provided to the component's
  # setup as `__pv`, so a page can mount the same component several times.
  defp exports(classification) do
    """

    export { __component as default };

    // The models, which the component may change: a change shows at once, as
    // in a parent component, and the server's next props are the truth.
    const __models = #{Jason.encode!(Map.get(classification, :models, []))};

    export function __mount(el, bridge, props = {}) {
      const state = __reactive({ ...props });
      const listeners = Object.fromEntries(
        __models.map((model) => ["onUpdate:" + model, (value) => { state[model] = value; }])
      );
      // Rendering through h() reads the props inside the root render effect,
      // so applyProps re-renders. createApp(component, props) would copy them.
      const app = __createApp({ render: () => __h(__component, { ...state, ...listeners }) });
      // While a session is recorded, the bridge reports the refs setup registers.
      const record = (sources) => bridge.record?.(sources, __watch, __unref);
      app.provide("__pv", { bridge, props: state, record });
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

  # Setup injects its mount's `__pv`, and registers its refs before it returns.
  defp setup_patches(ast, refs) do
    ast
    |> OXC.collect(fn
      %{type: :export_default_declaration, declaration: %{type: :object_expression} = component} ->
        patches =
          for %{type: :property, key: %{name: "setup"}, value: %{body: body}} <-
                component.properties,
              patch <- [
                patch(body.start + 1, body.start + 1, ~s|\n  const __pv = __inject("__pv");|)
                | record_patch(body, refs)
              ],
              do: patch

        {:keep, patches}

      _ ->
        :skip
    end)
    |> List.flatten()
  end

  defp record_patch(_body, []), do: []

  defp record_patch(%{body: statements}, refs) do
    case List.last(statements) do
      %{type: :return_statement, start: start} ->
        [patch(start, start, "__pv?.record({ #{Enum.join(refs, ", ")} });\n")]

      _other ->
        []
    end
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

  # The action's params are taken on entry, as the JSON the server will get,
  # so the body can change what it reads. The body runs as written, so a
  # model it writes changes at once; then the server gets the action. A
  # `return` or a `throw` in the body, such as a guard, stops it before it
  # reaches the server.
  defp server_action_patch(%{id: %{name: name}, params: params, body: body}, code, classification) do
    capture =
      "const __pvParams = JSON.parse(JSON.stringify(#{event_params(body, params, code, classification)}));"

    action = "__pv.bridge.action(#{Jason.encode!(name)}, __pvParams);"

    start =
      case body.body do
        [%{directive: "use server", end: directive_end} | _rest] -> directive_end
        _statements -> body.start + 1
      end

    statements = slice(code, %{start: start, end: body.end - 1})

    patch(
      body.start + 1,
      body.end - 1,
      IO.iodata_to_binary(["\n  ", capture, statements, "\n  ", action, "\n"])
    )
  end

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
end
