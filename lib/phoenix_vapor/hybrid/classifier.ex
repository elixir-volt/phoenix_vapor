defmodule PhoenixVapor.Hybrid.Classifier do
  @moduledoc false

  # Classifies bindings from a parsed `<script setup>` into server-owned,
  # client-owned, and mixed categories using AST-based dataflow analysis.
  #
  # Given a `PhoenixVapor.Compiler.ScriptSetup`, determines:
  # - Which props the client needs (for serialization)
  # - Which functions are server actions vs client handlers
  # - Which computeds are pure-client vs mixed (depend on server props)

  alias PhoenixVapor.Compiler.ScriptSetup
  alias PhoenixVapor.JS.FreeNames

  @type binding_kind ::
          :server_prop
          | {:client_ref, initial :: String.t()}
          | :client_computed
          | {:mixed_computed, server_deps :: [String.t()], client_deps :: [String.t()]}

  @type handler_kind ::
          :client_handler
          | {:server_action, body :: String.t()}

  @type classification :: %{
          bindings: %{String.t() => binding_kind()},
          handlers: %{String.t() => handler_kind()},
          client_props: [String.t()],
          server_only_props: [String.t()],
          models: [String.t()]
        }

  @doc """
  Classifies the bindings and handlers a `<script setup>` declares, given
  the names the template reads, with `props.x` as `x`; see
  `PhoenixVapor.Renderer.reads/1`.
  """
  @spec classify(ScriptSetup.t(), [String.t()]) :: classification()
  def classify(%ScriptSetup{} = setup, template_names \\ []) do
    %{refs: refs, computeds: computeds, functions: function_bodies, models: models} = setup
    # A model is a prop the browser may change, so the server sends it too.
    models = Map.keys(models)
    props = setup.props ++ models
    prop_set = MapSet.new(props)
    ref_set = MapSet.new(Map.keys(refs))

    bindings =
      build_bindings(props, refs, computeds, prop_set, ref_set)

    handlers = build_handlers(function_bodies, MapSet.new(models))

    client_props =
      compute_client_props(bindings, handlers, function_bodies, refs, props, template_names)
      |> Enum.concat(models)
      |> Enum.uniq()

    server_only_props = props -- client_props

    %{
      bindings: bindings,
      handlers: handlers,
      client_props: client_props,
      server_only_props: server_only_props,
      models: models
    }
  end

  defp build_bindings(props, refs, computeds, prop_set, ref_set) do
    prop_bindings = Map.new(props, fn p -> {p, :server_prop} end)
    ref_bindings = Map.new(refs, fn {name, init} -> {name, {:client_ref, init}} end)

    computed_bindings =
      Map.new(computeds, fn {name, expr} ->
        free = free_variables(expr)
        prop_refs = prop_references(expr)

        server_deps =
          ((free |> Enum.filter(&MapSet.member?(prop_set, &1))) ++
             (prop_refs |> Enum.filter(&MapSet.member?(prop_set, &1))))
          |> Enum.uniq()

        client_deps = free |> Enum.filter(&MapSet.member?(ref_set, &1))

        kind =
          if server_deps == [] do
            :client_computed
          else
            {:mixed_computed, server_deps, client_deps}
          end

        {name, kind}
      end)

    prop_bindings
    |> Map.merge(ref_bindings)
    |> Map.merge(computed_bindings)
  end

  # Each body is parsed once: a `"use server"` directive, or a write to a
  # model, which the server owns, makes it a server action.
  # A body is parsed as a function's, so it may `return`.
  @wrapper "function __handler() {\n"

  defp build_handlers(function_bodies, model_set) do
    Map.new(function_bodies, fn {name, body} ->
      kind =
        case OXC.parse(@wrapper <> body <> "\n}", "fn.js") do
          {:ok, %{body: [%{body: %{body: statements}} = function]}} ->
            handler_kind(body, statements, function, model_set)

          _error ->
            :client_handler
        end

      {name, kind}
    end)
  end

  defp handler_kind(body, [first | _rest], function, model_set) do
    cond do
      use_server?(first) ->
        {:server_action, after_directive(body, first.end - byte_size(@wrapper))}

      writes_to_model?(function, model_set) ->
        {:server_action, body}

      true ->
        :client_handler
    end
  end

  defp handler_kind(_body, [], _function, _model_set), do: :client_handler

  defp use_server?(%{type: :expression_statement, directive: "use server"}), do: true

  defp use_server?(%{
         type: :expression_statement,
         expression: %{type: :literal, value: "use server"}
       }),
       do: true

  defp use_server?(_statement), do: false

  defp after_directive(body, directive_end) do
    body
    |> binary_part(directive_end, byte_size(body) - directive_end)
    |> String.trim_leading(";")
    |> String.trim()
  end

  # `model.value = ...`, or `model.value++`.
  defp writes_to_model?(ast, model_set) do
    ast
    |> OXC.collect(fn
      %{type: :assignment_expression, left: target} -> {:keep, model_target(target)}
      %{type: :update_expression, argument: target} -> {:keep, model_target(target)}
      _node -> :skip
    end)
    |> Enum.any?(&MapSet.member?(model_set, &1))
  end

  defp model_target(%{
         type: :member_expression,
         object: %{type: :identifier, name: name},
         property: %{name: "value"}
       }),
       do: name

  defp model_target(_target), do: nil

  # The client renders the whole component and runs its functions, so it
  # needs every prop that the template or the script reads. A prop nothing
  # reads stays on the server. A template that reads `props` whole, as `v-bind="props"`
  # does, needs them all.
  defp compute_client_props(bindings, handlers, function_bodies, refs, props, template_names) do
    computed_deps =
      Enum.flat_map(bindings, fn
        {_name, {:mixed_computed, server_deps, _}} -> server_deps
        _ -> []
      end)

    # Server actions' bodies run in the browser too, before the server gets
    # the action.
    client_code = Map.values(refs) ++ for({name, _kind} <- handlers, do: function_bodies[name])

    read =
      client_code
      |> Enum.flat_map(&(free_variables(&1) ++ prop_references(&1)))
      |> Enum.concat(computed_deps ++ template_names)
      |> MapSet.new()

    if "props" in template_names,
      do: props,
      else: Enum.filter(props, &MapSet.member?(read, &1))
  end

  @doc """
  The props a JavaScript expression or function body reads as `props.x`, as
  with `const props = defineProps([...])`.
  """
  @spec prop_references(String.t()) :: [String.t()]
  def prop_references(source) do
    for "props." <> prop <- source |> parse() |> FreeNames.of(props: true),
        uniq: true,
        do: prop
  end

  @doc "The free names a JavaScript expression or function body reads."
  @spec free_variables(String.t()) :: [String.t()]
  def free_variables(source), do: source |> parse() |> FreeNames.of() |> Enum.sort()

  # An expression or statements, or else a function body, which may `return`.
  defp parse(source) do
    with {:error, _errors} <- OXC.parse(source, "e.js"),
         {:error, _errors} <- OXC.parse("function __wrapper() #{source}", "e.js") do
      nil
    else
      {:ok, ast} -> ast
    end
  end
end
