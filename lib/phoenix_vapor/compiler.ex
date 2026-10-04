defmodule PhoenixVapor.Compiler do
  @moduledoc false

  # Compiles a template for the server and resolves the components it uses.
  #
  # A component the SFC imports from a `.vue` file is compiled from that
  # file's template, recursively, and rendered on the server with its props,
  # slots, and fallthrough attributes. A component imported from anywhere
  # else, such as a package, can't be rendered by the server, and is reported
  # as a diagnostic. A component that isn't imported at all is looked up in the
  # `__components__` assign when the template renders.

  alias PhoenixVapor.Template
  alias PhoenixVapor.Compiler.{Macros, Packages, Split}
  alias PhoenixVapor.Renderer.Expr

  @typedoc """
  A problem found while compiling, in the shape of `t:Code.diagnostic/1`.
  Severity `:unrendered` marks what the server can't render: an error, except
  in hybrid mode, where the browser renders it.
  """
  @type diagnostic :: %{
          file: Path.t() | nil,
          severity: :error | :warning | :unrendered,
          message: String.t(),
          position: Template.position() | 0
        }

  @doc """
  Splits and compiles `template`, resolving the components its SFC imports.

  ## Options

    * `:file` — the SFC's path, for relative imports and diagnostics
    * `:origin` — `{line, column}` where the template starts in `:file`
    * `:script` — the SFC's `<script setup>` source, for its imports
    * `:events` — passed to `PhoenixVapor.Renderer.compile/2`
    * `:known` — values names have at compile time, such as a hybrid
      component's initial ref values, for rendering package components
    * `:elixir` — `{module, functions}`: the module the template renders in
      and the functions its SFC's `<script lang="elixir">` defines, from
      `PhoenixVapor.Compiler.SFC.elixir_functions/2`. A call to a `<script setup>`
      function renders through the Elixir function of the same name in
      snake_case, such as `role_tone/1` for `roleTone(role)`.
    * `:fold` — `:all` renders package components into their markup, for
      hybrid templates the browser takes over; `:content`, the default,
      only those that render just their content. See `PhoenixVapor.Compiler.Packages`.

  Returns the compiled template, the `.vue` files it read, and diagnostics.
  """
  @spec compile(String.t(), keyword()) :: {Template.t(), [Path.t()], [diagnostic()]}
  def compile(template, opts \\ []) do
    state = %{
      events: Keyword.get(opts, :events, true),
      fold: Keyword.get(opts, :fold, :content),
      stack: [],
      cache: %{},
      resources: [],
      diagnostics: [],
      macros: nil,
      quickbeam: nil
    }

    source = %{
      template: template,
      origin: Keyword.get(opts, :origin, {1, 1}),
      file: opts[:file],
      script: opts[:script] || "",
      elixir: opts[:elixir]
    }

    known = Keyword.get(opts, :known, %{})

    {compiled, state} =
      try do
        compile_template(source, [], nil, known, state)
      after
        # Each QuickBEAM runtime is only needed while compiling.
        Macros.stop(state.macros)
      end

    if state.quickbeam, do: QuickBEAM.stop(state.quickbeam.runtime)
    diagnostics = state.diagnostics |> Enum.reverse() |> Enum.uniq_by(&{&1.file, &1.message})
    {compiled, Enum.uniq(state.resources), diagnostics}
  end

  @doc """
  Like `compile/2`, but reports the diagnostics: warnings through `IO.warn/2`
  and errors as a `CompileError`. `unrendered: :warn`, for templates the
  browser renders again, reports what the server can't render as warnings.

  Returns the template and the `.vue` files it read.
  """
  @spec compile!(String.t(), keyword()) :: {Template.t(), [Path.t()]}
  def compile!(template, opts) do
    {compiled, resources, diagnostics} = compile(template, opts)

    {errors, warnings} =
      Enum.split_with(diagnostics, fn
        %{severity: :unrendered} -> opts[:unrendered] != :warn
        %{severity: severity} -> severity == :error
      end)

    Enum.each(warnings, fn
      %{severity: :unrendered} = diagnostic ->
        warn(%{
          diagnostic
          | message: diagnostic.message <> "; the browser renders it when it mounts"
        })

      diagnostic ->
        warn(diagnostic)
    end)

    case errors do
      [] -> {compiled, resources}
      errors -> raise_errors(errors)
    end
  end

  defp warn(%{message: message} = diagnostic) do
    IO.warn(message, location(diagnostic))
  end

  @spec raise_errors([diagnostic()]) :: no_return()
  defp raise_errors([first | rest]) do
    # CompileError shows the first error's file and line itself.
    description = Enum.map_join([first.message | Enum.map(rest, &format/1)], "\n", & &1)
    raise CompileError, [description: description] ++ location(first)
  end

  defp location(%{file: file, position: {line, _column}}) when is_binary(file),
    do: [file: file, line: line]

  defp location(%{file: file}) when is_binary(file), do: [file: file, line: 0]
  defp location(_diagnostic), do: []

  @doc "Formats a diagnostic as `file:line:column: message`."
  @spec format(diagnostic()) :: String.t()
  def format(%{file: file, position: position, message: message}) do
    file = if file, do: Path.relative_to_cwd(file), else: "nofile"

    case position do
      {line, column} -> "#{file}:#{line}:#{column}: #{message}"
      _ -> "#{file}: #{message}"
    end
  end

  defp compile_template(source, split_opts, static_props, known, state) do
    split =
      case Vize.split_template(source.template, split_opts) do
        {:ok, split} ->
          split

        {:error, %Vize.Error{diagnostics: diagnostics}} ->
          diagnostics
          |> Enum.map(
            &Vize.Diagnostic.to_code_diagnostic(&1, file: source.file, origin: source.origin)
          )
          |> raise_errors()
      end

    state =
      Enum.reduce(split.diagnostics, state, fn diagnostic, state ->
        diagnostic =
          Vize.Diagnostic.to_code_diagnostic(diagnostic, file: source.file, origin: source.origin)

        add(state, Map.take(diagnostic, [:file, :severity, :message, :position]))
      end)

    compiled =
      Split.compile(split, events: state.events, file: source.file, origin: source.origin)

    ctx = %{
      file: source.file,
      imports: imports(source.script),
      script: source.script,
      static_props: static_props,
      known: known,
      elixir: source[:elixir]
    }

    {compiled, runtime, macro_diagnostics} = Macros.fold(compiled, ctx, state.macros)
    state = Enum.reduce(macro_diagnostics, %{state | macros: runtime}, &add(&2, &1))

    {compiled, state} = mark_script_calls(compiled, ctx, state)
    resolve_template(compiled, ctx, state)
  end

  defp resolve_template(%Template{slots: slots} = template, ctx, state) do
    {slots, state} = Enum.map_reduce(slots, state, &resolve_slot(&1, ctx, &2))
    {%{template | slots: slots}, state}
  end

  defp resolve_slot(%{kind: :if, branches: branches} = slot, ctx, state) do
    {branches, state} =
      Enum.map_reduce(branches, state, fn branch, state ->
        {block, state} = resolve_template(branch.block, ctx, state)
        {%{branch | block: block}, state}
      end)

    {%{slot | branches: branches}, state}
  end

  defp resolve_slot(%{kind: :for, block: block} = slot, ctx, state) do
    {block, state} = resolve_template(block, ctx, state)
    {%{slot | block: block}, state}
  end

  defp resolve_slot(%{kind: :slot, fallback: %Template{} = fallback} = slot, ctx, state) do
    {fallback, state} = resolve_template(fallback, ctx, state)
    {%{slot | fallback: fallback}, state}
  end

  defp resolve_slot(%{kind: :fragment, template: template} = slot, ctx, state) do
    {template, state} = resolve_template(template, ctx, state)
    {%{slot | template: template}, state}
  end

  # A package component renders at compile time, with any package components
  # inside it, before the template's own content inside it is resolved.
  defp resolve_slot(%{kind: :component, name: name} = slot, ctx, state) do
    case package(ctx, name) do
      nil -> resolve_local(slot, ctx, state)
      package -> fold(slot, package, ctx, state)
    end
  end

  defp resolve_slot(slot, _ctx, state), do: {slot, state}

  defp resolve_local(%{slots: contents} = slot, ctx, state) do
    {contents, state} =
      Enum.map_reduce(contents, state, fn content, state ->
        {block, state} = resolve_template(content.block, ctx, state)
        {%{content | block: block}, state}
      end)

    resolve_component(%{slot | slots: contents}, ctx, state)
  end

  defp fold(slot, package, ctx, state) do
    case ensure_fold(ctx, state) do
      {:ok, state} ->
        case Packages.fold(
               slot,
               &package(ctx, &1),
               ctx.known,
               state.quickbeam.runtime,
               ctx.file,
               state.fold
             ) do
          {:ok, fragment} -> resolve_slot(fragment, ctx, state)
          {:error, reason} -> unfoldable(slot, package, reason, ctx, state)
        end

      {:error, reason, state} ->
        unfoldable(slot, package, reason, ctx, state)
    end
  end

  defp unfoldable(%{name: name} = slot, package, reason, ctx, state) do
    message = "<#{name}> from #{inspect(package.source)} can't render on the server: #{reason}"
    {slot, diagnose(state, :unrendered, ctx.file, slot.position, message)}
  end

  # Vue's server renderer and the file's packages load once per file.
  defp ensure_fold(ctx, state) do
    %{runtime: runtime, loaded: loaded} =
      state.quickbeam || %{runtime: elem(QuickBEAM.start(), 1), loaded: MapSet.new()}

    state = %{state | quickbeam: %{runtime: runtime, loaded: loaded}}

    if MapSet.member?(loaded, ctx.file) do
      {:ok, state}
    else
      case Packages.load(runtime, package_sources(ctx), ctx.file) do
        :ok -> {:ok, put_in(state.quickbeam.loaded, MapSet.put(loaded, ctx.file))}
        {:error, reason} -> {:error, reason, state}
      end
    end
  end

  # The packages the file imports components from: imports named like
  # components, such as `TabsRoot`.
  defp package_sources(ctx) do
    for {name, %{source: source}} <- ctx.imports,
        name =~ ~r/\A[A-Z]/,
        package(ctx, name) != nil,
        uniq: true,
        do: source
  end

  # The package import for a component tag, or nil for a local or unknown one.
  defp package(ctx, tag) do
    case import_for(ctx.imports, tag) do
      %{source: source, attributes: attributes} = import ->
        if Path.extname(source) != ".vue" and attributes["type"] != "macro", do: import

      nil ->
        nil
    end
  end

  defp resolve_component(%{name: name} = slot, ctx, state) do
    case import_for(ctx.imports, name) do
      nil ->
        {slot, state}

      %{source: source} ->
        if Path.extname(source) == ".vue" do
          resolve_vue(slot, source, ctx, state)
        else
          message = "<#{name}> is imported from #{inspect(source)}, which the server can't render"
          {slot, diagnose(state, :unrendered, ctx.file, slot.position, message)}
        end
    end
  end

  defp resolve_vue(%{name: name} = slot, source, ctx, state) do
    case resolve_path(source, ctx.file) do
      {:ok, path} ->
        if path in state.stack do
          message = "<#{name}> renders itself, which the server can't do"
          {slot, diagnose(state, :unrendered, ctx.file, slot.position, message)}
        else
          static_props = static_props(slot.props)

          case state.cache[{path, static_props}] do
            nil ->
              {compiled, state} = compile_child(path, static_props, state)
              state = %{state | cache: Map.put(state.cache, {path, static_props}, compiled)}
              {Map.put(slot, :component, compiled), state}

            compiled ->
              {Map.put(slot, :component, compiled), state}
          end
        end

      {:error, _reason} ->
        message = "can't find #{inspect(source)}, imported for <#{name}>"
        {slot, diagnose(state, :error, ctx.file, slot.position, message)}
    end
  end

  # A call to a function `<script setup>` defines or imports, other than a
  # macro, runs only in the browser, unless the SFC's `<script lang="elixir">`
  # defines the same function, named in snake_case, for the server.
  defp mark_script_calls(template, ctx, state) do
    case browser_functions(ctx.script, ctx.imports) do
      [] ->
        {template, state}

      functions ->
        Template.map_exprs(template, state, fn
          {:expr, source, node, _keys} = expr, slot, state when is_map(node) ->
            rewritten = elixir_calls(node, functions, ctx.elixir)

            case called(rewritten, functions) do
              nil when rewritten == node ->
                {expr, state}

              nil ->
                {{:expr, source, rewritten, Expr.free_names(rewritten)}, state}

              name ->
                message =
                  "`#{source}` calls #{name}, which runs only in the browser" <>
                    elixir_hint(name, ctx)

                {{:unrendered, source},
                 diagnose(state, :unrendered, ctx.file, slot[:position], message)}
            end

          expr, _slot, state ->
            {expr, state}
        end)
    end
  end

  # Points calls to `functions` at their Elixir counterparts.
  defp elixir_calls(node, _functions, nil), do: node

  defp elixir_calls(node, functions, {module, elixir}) do
    rewrite(node, fn
      %{type: :call_expression, callee: %{type: :identifier, name: name}, arguments: args} = call ->
        server = Macro.underscore(name)

        if name in functions and
             MapSet.member?(Map.get(elixir, server, MapSet.new()), length(args)),
           do: %{
             call
             | callee: %{
                 type: :elixir_function,
                 module: module,
                 function: String.to_existing_atom(server)
               }
           },
           else: call

      other ->
        other
    end)
  end

  defp rewrite(%{} = node, fun) do
    node |> fun.() |> Map.new(fn {key, value} -> {key, rewrite(value, fun)} end)
  end

  defp rewrite(list, fun) when is_list(list), do: Enum.map(list, &rewrite(&1, fun))
  defp rewrite(value, _fun), do: value

  defp elixir_hint(name, %{elixir: {_module, _functions}}),
    do:
      "; define #{Macro.underscore(name)} in <script lang=\"elixir\"> to render it on the server"

  defp elixir_hint(_name, _ctx), do: ""

  defp browser_functions(script, imports) do
    imported =
      for {name, %{source: source} = import} <- imports,
          Path.extname(source) != ".vue",
          import.attributes["type"] != "macro",
          do: name

    declared =
      case OXC.parse(script, "setup.ts") do
        {:ok, ast} ->
          OXC.collect(ast, fn
            %{type: :function_declaration, id: %{name: name}} ->
              {:keep, name}

            %{type: :variable_declarator, id: %{name: name}, init: %{type: type}}
            when type in [:arrow_function_expression, :function_expression] ->
              {:keep, name}

            _ ->
              :skip
          end)

        _ ->
          []
      end

    Enum.uniq(imported ++ declared)
  end

  # The first of `functions` the expression calls, directly or as a namespace.
  defp called(node, functions) do
    node
    |> OXC.collect(fn
      %{type: :call_expression, callee: %{type: :identifier, name: name}} ->
        {:keep, name}

      %{type: :call_expression, callee: %{object: %{type: :identifier, name: name}}} ->
        {:keep, name}

      _ ->
        :skip
    end)
    |> Enum.find(&(&1 in functions))
  end

  defp diagnose(state, severity, file, position, message),
    do: add(state, %{file: file, severity: severity, message: message, position: position || 0})

  defp add(state, diagnostic), do: %{state | diagnostics: [diagnostic | state.diagnostics]}

  # What a component instance knows about its props at compile time: values
  # passed as constants, such as `variant="ghost"` or `:size="'sm'"`, and the
  # names bound to anything else. A prop that isn't passed is `undefined`. A
  # component is compiled once for each combination, so macro calls that use
  # its props can fold.
  defp static_props(props) do
    Enum.reduce(props, %{static: %{}, dynamic: MapSet.new()}, fn
      %{name: name, static: static, value: nil, name_value: nil}, acc when name != nil ->
        put_in(acc, [:static, camelize(name)], static)

      %{name: name, value: {:expr, _source, %{type: :literal, value: value}, _keys}}, acc
      when name != nil ->
        put_in(acc, [:static, camelize(name)], value)

      %{name: name}, acc when name != nil ->
        %{acc | dynamic: MapSet.put(acc.dynamic, camelize(name))}

      _spread_or_dynamic_name, acc ->
        acc
    end)
  end

  defp camelize(key), do: Regex.replace(~r/-(\w)/, key, fn _, char -> String.upcase(char) end)

  defp compile_child(path, static_props, state) do
    source = File.read!(path)
    desc = Vize.parse_sfc!(source)
    script = (desc.script_setup && desc.script_setup.content) || ""
    {template, origin} = PhoenixVapor.Compiler.SFC.template(desc) || {"", {1, 1}}

    parent_stack = state.stack
    state = %{state | stack: [path | parent_stack], resources: [path | state.resources]}

    # The props passed as constants are known when its package components
    # render. Only a component with macros needs the rest of what's known.
    known = static_props.static

    static_props =
      if Macros.any?(imports(script)),
        do: Map.put(static_props, :declared, props(source)),
        else: nil

    child = %{template: template, origin: origin, file: path, script: script}
    {compiled, state} = compile_template(child, [root_attrs: true], static_props, known, state)

    component = %{props: props(source), template: compiled, events: state.events}
    {component, %{state | stack: parent_stack}}
  end

  defp props(source) do
    case Vize.analyze_sfc(source) do
      {:ok, croquis} -> Enum.map(croquis.props, & &1.name)
      {:error, _} -> []
    end
  end

  # Volt resolves the specifier the way the browser build does: relative to
  # the importing file, or through the project's aliases such as `@/`.
  defp resolve_path(source, importer) do
    opts = [importer: importer, aliases: aliases()]

    case Volt.Assets.resolve(source, opts) do
      {:ok, path} -> {:ok, Path.expand(path)}
      error -> error
    end
  end

  defp aliases do
    if Code.ensure_loaded?(Volt.Config), do: Volt.Config.build().aliases, else: %{}
  end

  # A tag matches the import with its name, in either case style: `<my-card>`
  # uses `MyCard`.
  defp import_for(imports, tag) do
    imports[tag] || imports[tag |> String.replace("-", "_") |> Macro.camelize()]
  end

  # The bindings a `<script setup>` imports: local name to source and
  # import attributes.
  @spec imports(String.t()) :: %{String.t() => map()}
  defp imports(script) do
    case OXC.parse(script, "setup.ts") do
      {:ok, ast} ->
        ast
        |> OXC.collect(fn
          %{type: :import_declaration, source: %{value: source}} = decl ->
            {:keep, decl_imports(decl, source)}

          _ ->
            :skip
        end)
        |> List.flatten()
        |> Map.new()

      _ ->
        %{}
    end
  end

  defp decl_imports(decl, source) do
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
end
