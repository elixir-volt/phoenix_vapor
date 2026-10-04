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
  alias PhoenixVapor.Compiler.{Macros, Packages, PropTypes, ScriptSetup, SFC, Split}
  alias PhoenixVapor.JS.Session
  alias PhoenixVapor.Renderer.{Expr, Names}

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
  Splits and compiles a `.vue` file's template, or a template string,
  resolving the components its SFC imports.

  ## Options

    * `:target` — `:server`, the default, for a template only the server
      renders: events become `phx-*` attributes, and what the server can't
      render is an error. `:browser`, for a hybrid template the browser takes
      over: the client handles events, package components render into their
      markup with the refs' initial values, which the browser renders first
      too, and what the server can't render is left to the browser.
    * `:module` — the module the template renders in. A call to a `<script
      setup>` function renders through the function of the same name in
      snake_case that the SFC's `<script lang="elixir">` defines, such as
      `role_tone/1` for `roleTone(role)`.

  For a template string:

    * `:file` — the SFC's path, for relative imports and diagnostics
    * `:origin` — `{line, column}` where the template starts in `:file`
    * `:script` — the SFC's `<script setup>` source

  Returns the compiled template, the `.vue` files it read, and diagnostics.
  """
  @spec compile(SFC.t() | String.t(), keyword()) :: {Template.t(), [Path.t()], [diagnostic()]}
  def compile(template, opts \\ [])

  def compile(%SFC{} = sfc, opts) do
    elixir = if opts[:module], do: {opts[:module], SFC.elixir_functions(sfc)}

    compile_sfc(
      %{sfc | template: SFC.template!(sfc)},
      elixir,
      Keyword.get(opts, :target, :server)
    )
  end

  def compile(template, opts) when is_binary(template) do
    sfc = %SFC{
      file: opts[:file],
      source: template,
      template: template,
      origin: Keyword.get(opts, :origin, {1, 1}),
      setup: ScriptSetup.parse(opts[:script])
    }

    compile_sfc(sfc, nil, Keyword.get(opts, :target, :server))
  end

  defp compile_sfc(sfc, elixir, target) do
    state = %{
      events: target == :server,
      fold: if(target == :browser, do: :all, else: :content),
      stack: [],
      cache: %{},
      resources: [],
      diagnostics: [],
      js: nil
    }

    # Macros, package components and prop types share one QuickBEAM runtime,
    # only while compiling.
    {compiled, state} =
      Session.with_session(PropTypes.handlers(), fn session ->
        known = if target == :browser, do: initial_values(sfc.setup, session), else: %{}
        compile_template(sfc, nil, known, %{state | js: session}, elixir: elixir)
      end)

    diagnostics = state.diagnostics |> Enum.reverse() |> Enum.uniq_by(&{&1.file, &1.message})
    {compiled, Enum.uniq(state.resources), diagnostics}
  end

  # The browser's first render uses the refs' initial values, so package
  # components render with them on the server too.
  defp initial_values(setup, session) do
    setup.refs
    |> ScriptSetup.eval_initial_state(Session.runtime(session))
    |> Map.new(fn {name, value} -> {Atom.to_string(name), value} end)
  end

  @doc """
  Like `compile/2`, but reports the diagnostics: warnings through `IO.warn/2`
  and errors as a `CompileError`. For the `:browser` target, which the browser
  renders again, what the server can't render is a warning.

  Returns the template and the `.vue` files it read.
  """
  @spec compile!(SFC.t() | String.t(), keyword()) :: {Template.t(), [Path.t()]}
  def compile!(template, opts \\ []) do
    {compiled, resources, diagnostics} = compile(template, opts)
    browser? = opts[:target] == :browser

    {errors, warnings} =
      Enum.split_with(diagnostics, fn
        %{severity: :unrendered} -> not browser?
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

  # A template, for the file it's in or as a child component of it, with the
  # props passed to it as constants, if a child, and the names known at
  # compile time. `:root_attrs` is for a child, whose root element takes the
  # attributes that fall through; `:elixir` is for the LiveView's own file.
  defp compile_template(%SFC{} = source, static_props, known, state, opts) do
    split =
      case Vize.split_template(source.template, Keyword.take(opts, [:root_attrs])) do
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
      setup: source.setup,
      static_props: static_props,
      known: known,
      elixir: opts[:elixir]
    }

    {compiled, macro_diagnostics} = Macros.fold(compiled, ctx, state.js)
    state = Enum.reduce(macro_diagnostics, state, &add(&2, &1))

    {compiled, state} = mark_script_calls(compiled, ctx, state)
    resolve_template(compiled, ctx, state)
  end

  defp resolve_template(%Template{slots: slots} = template, ctx, state) do
    {slots, state} = Enum.map_reduce(slots, state, &resolve_slot(&1, ctx, &2))
    {%{template | slots: slots}, state}
  end

  # A package component renders at compile time, with any package components
  # inside it, before the template's own content inside it is resolved.
  defp resolve_slot(%{kind: :component, name: name} = slot, ctx, state) do
    case package(ctx, name) do
      nil ->
        {slot, state} = resolve_blocks(slot, ctx, state)
        resolve_component(slot, ctx, state)

      package ->
        fold(slot, package, ctx, state)
    end
  end

  defp resolve_slot(slot, ctx, state), do: resolve_blocks(slot, ctx, state)

  defp resolve_blocks(slot, ctx, state),
    do: Template.map_blocks(slot, state, &resolve_template(&1, ctx, &2))

  # Vue's server renderer and the file's packages load once per file.
  defp fold(slot, package, ctx, state) do
    load = &Packages.load(&1, package_sources(ctx), ctx.file)
    runtime = Session.runtime(state.js)

    with :ok <- Session.once(state.js, {:packages, ctx.file}, load),
         {:ok, fragment} <-
           Packages.fold(slot, &package(ctx, &1), ctx.known, runtime, ctx.file, state.fold) do
      resolve_slot(fragment, ctx, state)
    else
      {:error, reason} -> unfoldable(slot, package, reason, ctx, state)
    end
  end

  defp unfoldable(%{name: name} = slot, package, reason, ctx, state) do
    message = "<#{name}> from #{inspect(package.source)} can't render on the server: #{reason}"
    {slot, diagnose(state, :unrendered, ctx.file, slot.position, message)}
  end

  # The packages the file imports components from: imports named like
  # components, such as `TabsRoot`.
  defp package_sources(ctx) do
    for {name, %{source: source}} <- ctx.setup.imports,
        name =~ ~r/\A[A-Z]/,
        package(ctx, name) != nil,
        uniq: true,
        do: source
  end

  # The package import for a component tag, or nil for a local or unknown one.
  defp package(ctx, tag) do
    case import_for(ctx.setup.imports, tag) do
      %{source: source, attributes: attributes} = import ->
        if Path.extname(source) != ".vue" and attributes["type"] != "macro", do: import

      nil ->
        nil
    end
  end

  defp resolve_component(%{name: name} = slot, ctx, state) do
    case import_for(ctx.setup.imports, name) do
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
    case browser_functions(ctx.setup) do
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

  defp browser_functions(setup) do
    imported =
      for {name, %{source: source} = import} <- setup.imports,
          Path.extname(source) != ".vue",
          import.attributes["type"] != "macro",
          do: name

    Enum.uniq(imported ++ setup.callables)
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
        put_in(acc, [:static, Names.camelize(name)], static)

      %{name: name, value: {:expr, _source, %{type: :literal, value: value}, _keys}}, acc
      when name != nil ->
        put_in(acc, [:static, Names.camelize(name)], value)

      %{name: name}, acc when name != nil ->
        %{acc | dynamic: MapSet.put(acc.dynamic, Names.camelize(name))}

      _spread_or_dynamic_name, acc ->
        acc
    end)
  end

  defp compile_child(path, static_props, state) do
    sfc = SFC.read!(path)

    parent_stack = state.stack
    state = %{state | stack: [path | parent_stack], resources: [path | state.resources]}

    # The props passed as constants are known when its package components
    # render. Only a component with macros needs the rest of what's known.
    known = static_props.static

    static_props =
      if Macros.any?(sfc.setup.imports),
        do: Map.put(static_props, :declared, sfc.setup.props),
        else: nil

    {compiled, state} =
      compile_template(%{sfc | template: sfc.template || ""}, static_props, known, state,
        root_attrs: true
      )

    component = %{props: sfc.setup.props, template: compiled, events: state.events}
    {component, %{state | stack: parent_stack}}
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
end
