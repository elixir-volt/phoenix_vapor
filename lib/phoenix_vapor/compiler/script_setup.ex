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
          props: [String.t()]
        }

  defstruct source: "",
            imports: %{},
            refs: %{},
            computeds: %{},
            functions: %{},
            consts: [],
            callables: [],
            props: []

  @doc """
  Reads a `<script setup>` block. A script that doesn't parse declares
  nothing; the browser build reports its syntax error.

    * `:refs` — `ref()` initial expressions by name
    * `:computeds` — `computed()` bodies by name, an expression or a block
    * `:functions` — function declarations' bodies by name
    * `:consts` — top-level `const` declarations, in order, with their
      initializer's node and source
    * `:callables` — declared functions and arrow functions
    * `:props` — the props `defineProps` declares, in any of its forms
  """
  @spec parse(String.t() | nil) :: t()
  def parse(nil), do: %__MODULE__{}

  def parse(source) do
    case OXC.parse(source, "setup.ts") do
      {:ok, ast} ->
        %__MODULE__{
          source: source,
          imports: imports(ast),
          refs: calls(ast, source, "ref"),
          computeds: computeds(ast, source),
          functions: functions(ast, source),
          consts: consts(ast, source),
          callables: callables(ast),
          props: props(source)
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
