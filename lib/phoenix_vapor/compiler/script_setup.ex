defmodule PhoenixVapor.Compiler.ScriptSetup do
  @moduledoc false

  # What `<script setup>` declares, read once from its OXC AST: the imports,
  # `ref()` initial expressions, `computed()` bodies, functions with their
  # bodies, top-level constants, `defineProps`, and which names the template
  # calls as functions.

  alias PhoenixVapor.Renderer.Names

  @type import_spec :: %{
          source: String.t(),
          imported: :default | :namespace | String.t(),
          attributes: %{String.t() => String.t()}
        }

  @type t :: %__MODULE__{
          source: String.t(),
          imports: %{String.t() => import_spec()},
          refs: %{String.t() => String.t()},
          computeds: %{String.t() => String.t()},
          functions: %{String.t() => String.t()},
          consts: [{String.t(), map(), String.t()}],
          callables: [String.t()],
          client_bindings: [String.t()],
          offsets: %{String.t() => non_neg_integer()},
          props: [String.t()],
          models: %{String.t() => String.t()}
        }

  defstruct source: "",
            imports: %{},
            refs: %{},
            computeds: %{},
            functions: %{},
            consts: [],
            callables: [],
            client_bindings: [],
            offsets: %{},
            props: [],
            models: %{}

  @doc """
  Reads a `<script setup>` block. A script that doesn't parse declares
  nothing; the browser build reports its syntax error.

    * `:refs` — `ref()` initial expressions by name
    * `:computeds` — `computed()` bodies by name, an expression or a block
    * `:functions` — function declarations' bodies by name
    * `:consts` — top-level `const` declarations, in order, with their
      initializer's node and source
    * `:callables` — declared functions and arrow functions
    * `:client_bindings` — top-level names bound by a call the compiler
      can't run, such as a composable's (`const debounced = refDebounced(q)`,
      `const { copy, copied } = useClipboard()`) or `reactive()`; their values
      exist only in the browser. `ref()`s, with their initial values, are
      `:refs` instead.
    * `:props` — the props `defineProps` declares, in any of its forms
    * `:models` — the models `defineModel` declares, by the name they're
      bound to: `const open = defineModel("open")` is `%{"open" => "open"}`,
      and an unnamed `defineModel()` is the `"modelValue"` model
  """
  @spec parse(String.t() | nil) :: t()
  def parse(nil), do: %__MODULE__{}

  def parse(source) do
    case OXC.parse(source, "setup.ts") do
      {:ok, ast} ->
        imports = imports(ast)

        %__MODULE__{
          source: source,
          imports: imports,
          refs: calls(ast, source, "ref"),
          computeds: computeds(ast, source),
          functions: functions(ast, source),
          consts: consts(ast, source),
          callables: callables(ast),
          client_bindings: client_bindings(ast, imports),
          offsets: offsets(ast),
          props: props(source),
          models: models(ast)
        }

      {:error, _errors} ->
        %__MODULE__{source: source}
    end
  end

  @doc """
  The refs' initial values, evaluated in `runtime`, by atom. A ref whose
  initial expression fails, such as one reading a prop, starts as nil.
  """
  @spec eval_initial_state(%{String.t() => String.t()}, pid(), map()) :: map()
  def eval_initial_state(refs, runtime, assigns \\ %{}) do
    Enum.reduce(refs, assigns, fn {name, init_expr}, acc ->
      value =
        case QuickBEAM.eval(runtime, "(#{init_expr})") do
          {:ok, value} -> value
          {:error, _error} -> nil
        end

      Map.put(acc, Names.atom!(name), value)
    end)
  end

  defp imports(ast) do
    ast
    |> OXC.collect(fn
      %{type: :import_declaration, source: %{value: source}} = decl ->
        {:keep, import_specs(decl, source)}

      _node ->
        :skip
    end)
    |> List.flatten()
    |> Map.new()
  end

  defp import_specs(decl, source) do
    attributes =
      Map.new(decl[:attributes] || [], fn %{key: key, value: %{value: value}} ->
        {key[:name] || key[:value], value}
      end)

    for specifier <- decl[:specifiers] || [] do
      imported =
        case specifier do
          %{type: :import_default_specifier} -> :default
          %{type: :import_namespace_specifier} -> :namespace
          %{imported: %{name: name}} -> name
          %{imported: %{value: name}} -> name
        end

      {specifier.local.name, %{source: source, imported: imported, attributes: attributes}}
    end
  end

  # Where each top-level declaration starts in the script, for diagnostics.
  defp offsets(%{body: body}) do
    for statement <- body, name <- declared(statement), into: %{}, do: {name, statement.start}
  end

  defp declared(%{type: :variable_declaration, declarations: declarations}),
    do: Enum.flat_map(declarations, &binding_names(&1.id))

  defp declared(%{type: :function_declaration, id: %{name: name}}), do: [name]
  defp declared(_statement), do: []

  # `const name = defineModel(...)`: the model's name is the first argument
  # when it's a string, and `modelValue` otherwise.
  defp models(%{body: body}) do
    for %{type: :variable_declaration, declarations: declarations} <- body,
        %{id: %{type: :identifier, name: name}, init: %{type: :call_expression} = call} <-
          declarations,
        %{callee: %{type: :identifier, name: "defineModel"}} <- [call],
        into: %{},
        do: {name, model_name(call.arguments)}
  end

  defp model_name([%{type: :literal, value: name} | _rest]) when is_binary(name), do: name
  defp model_name(_arguments), do: "modelValue"

  # `const name = callee(arg)`: the first argument's source by name.
  defp calls(ast, source, callee) do
    for {name, %{type: :call_expression, callee: %{name: ^callee}, arguments: [arg | _]}} <-
          declarators(ast),
        into: %{},
        do: {name, slice(source, arg)}
  end

  defp computeds(ast, source) do
    for {name, %{type: :call_expression, callee: %{name: "computed"}, arguments: [arg | _]}} <-
          declarators(ast),
        %{type: :arrow_function_expression, body: body} <- [arg],
        into: %{},
        do: {name, slice(source, body)}
  end

  # Every `name = init` declarator, at any depth.
  defp declarators(ast) do
    OXC.collect(ast, fn
      %{type: :variable_declarator, id: %{type: :identifier, name: name}, init: %{} = init} ->
        {:keep, {name, init}}

      _node ->
        :skip
    end)
  end

  # A function declaration's body, without its braces.
  defp functions(ast, source) do
    ast
    |> OXC.collect(fn
      %{type: :function_declaration, id: %{name: name}, body: %{start: start, end: stop}} ->
        {:keep, {name, source |> binary_part(start + 1, stop - start - 2) |> String.trim()}}

      _node ->
        :skip
    end)
    |> Map.new()
  end

  defp consts(%{body: body}, source) do
    for %{type: :variable_declaration, kind: kind, declarations: declarations} <- body,
        kind in [:const, "const"],
        %{id: %{type: :identifier, name: name}, init: %{} = init} <- declarations,
        do: {name, init, slice(source, init)}
  end

  # Calls the compiler runs or understands: Vue's compiler macros, `ref()`,
  # `computed()`, and helpers imported as macros.
  @understood ~w(ref computed defineProps withDefaults defineModel defineEmits defineExpose
                 defineOptions defineSlots)

  defp client_bindings(%{body: body}, imports) do
    for %{type: :variable_declaration, declarations: declarations} <- body,
        %{id: id, init: %{type: :call_expression, callee: callee}} <- declarations,
        not understood?(callee, imports),
        name <- binding_names(id),
        do: name
  end

  defp understood?(%{type: :identifier, name: name}, imports),
    do: name in @understood or get_in(imports, [name, :attributes, "type"]) == "macro"

  defp understood?(_callee, _imports), do: false

  defp binding_names(%{type: :identifier, name: name}), do: [name]

  defp binding_names(%{type: :object_pattern, properties: properties}),
    do: Enum.flat_map(properties, &binding_names(&1[:value] || &1[:argument] || &1))

  defp binding_names(%{type: :array_pattern, elements: elements}),
    do: elements |> Enum.reject(&is_nil/1) |> Enum.flat_map(&binding_names/1)

  defp binding_names(%{type: :assignment_pattern, left: left}), do: binding_names(left)
  defp binding_names(%{type: :rest_element, argument: argument}), do: binding_names(argument)
  defp binding_names(_pattern), do: []

  defp callables(ast) do
    ast
    |> OXC.collect(fn
      %{type: :function_declaration, id: %{name: name}} ->
        {:keep, name}

      %{type: :variable_declarator, id: %{name: name}, init: %{type: type}}
      when type in [:arrow_function_expression, :function_expression] ->
        {:keep, name}

      _node ->
        :skip
    end)
    |> Enum.uniq()
  end

  # Vize's analysis reads every defineProps form: array, object, and
  # TypeScript type arguments.
  defp props(source) do
    case Vize.analyze_sfc(~s(<script setup lang="ts">\n) <> source <> "\n</script>") do
      {:ok, croquis} -> Enum.map(croquis.props, & &1.name)
      {:error, _error} -> []
    end
  end

  defp slice(source, %{start: start, end: stop}), do: binary_part(source, start, stop - start)
end
