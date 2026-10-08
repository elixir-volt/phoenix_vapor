defmodule PhoenixVapor.Hybrid do
  @moduledoc """
  Hybrid mode implementation — split reactivity between server and client.

  Use via the unified API:

      use PhoenixVapor, file: "Contacts.vue"

  ## How it works

  When a `.vue` file has `ref()` in `<script setup>`, the unified API
  (`use PhoenixVapor, file: "X.vue"`) routes here automatically.

  Generates `render/1`, `handle_event/3` stubs, and a client JS module.
  """

  alias PhoenixVapor.{Compiler, Renderer}
  alias PhoenixVapor.Compiler.{PropTypes, ScriptSetup, SFC}
  alias PhoenixVapor.Hybrid.{Classifier, ClientCodegen, Computeds, ServerCodegen}
  alias PhoenixVapor.JS.Session
  alias PhoenixVapor.Renderer.{Expr, Names}

  defmacro __using__(opts) do
    opts |> Keyword.fetch!(:file) |> SFC.load!(__CALLER__) |> build(opts, __CALLER__)
  end

  @doc false
  # The LiveView for a hybrid `.vue` file: `render/1`, `handle_event/3`
  # stubs, and its client module.
  @spec build(SFC.t(), keyword(), Macro.Env.t()) :: Macro.t()
  def build(%SFC{} = sfc, opts, caller) do
    check_models!(sfc)
    check_prop_writes!(sfc)
    elixir = {caller.module, SFC.elixir_functions(sfc)}

    # The browser's first render uses the refs' initial values, the
    # component's constants, and the computeds of only those, so they're
    # evaluated once here, and package components render with them.
    {split, component_files, values, constants, plan} =
      Session.with_session(PropTypes.handlers(), fn session ->
        runtime = Session.runtime(session)
        constants = constants(sfc.setup, runtime)

        plan =
          Computeds.compile(sfc.setup,
            twins: twins(sfc, caller.module),
            known: Enum.map(Map.keys(constants), &Atom.to_string/1),
            rewrite: &Compiler.elixir_calls(&1, sfc.setup.callables, elixir)
          )

        Enum.each(plan.left_out, &warn_left_out(&1, sfc))
        warn_skipped_twins(plan, sfc)

        refs = ScriptSetup.eval_initial_state(sfc.setup.refs, runtime)
        values = constant_values(plan.constant, refs, constants, runtime, sfc.file)

        known =
          constants
          |> Map.merge(values)
          |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)

        {split, files} =
          Compiler.compile!(sfc,
            target: :browser,
            module: caller.module,
            session: session,
            known: known,
            constants: Enum.map(Map.keys(constants), &Atom.to_string/1),
            browser_only: Enum.map(plan.left_out, &elem(&1, 0))
          )

        {split, files, values, constants, plan}
      end)

    %{constant: constant, per_render: per_render} = plan

    classification = Classifier.classify(sfc.setup, Renderer.reads(split))
    component_name = Path.basename(sfc.file, ".vue")
    recorded = recorded(sfc, split, plan)

    render_ast =
      ServerCodegen.gen_render(split, classification,
        values: values,
        constants: constants,
        constant: constant,
        computeds: per_render,
        component: component_name,
        recorded: recorded,
        client: sfc.setup.client_bindings
      )

    event_asts = ServerCodegen.gen_handle_events(classification)

    client_output_dir = Keyword.get(opts, :client_output, default_client_output())

    {client_js, client_path} =
      generate_client_js(sfc, classification, recorded, client_output_dir)

    escaped_classification = Macro.escape(classification)
    escaped_client_js = Macro.escape(client_js)

    quote do
      @__hybrid_classification__ unquote(escaped_classification)
      @__hybrid_client_js__ unquote(escaped_client_js)
      @external_resource unquote(sfc.file)
      for file <- unquote(component_files), do: @external_resource(file)

      import PhoenixVapor.Sigil

      unquote(render_ast)
      unquote_splicing(event_asts)
      unquote_splicing(sfc.elixir)

      @doc "Returns the client JavaScript module generated for this component."
      def __hybrid_client_js__, do: @__hybrid_client_js__

      @doc "Returns how the component's bindings and handlers were split between server and client."
      def __hybrid_classification__, do: @__hybrid_classification__

      unquote(recompile_ast(client_path))
    end
  end

  # The client module is written while compiling, so a build that is up to
  # date, such as one a CI cache restores beside a fresh checkout, never
  # writes it again. Mix recompiles a module whose `__mix_recompile__?/0`
  # says so.
  defp recompile_ast(nil), do: nil

  defp recompile_ast(path) do
    quote do
      @doc "Whether Mix recompiles this LiveView: while its client module is missing."
      def __mix_recompile__?, do: not File.exists?(unquote(path))
    end
  end

  # A LiveView's callbacks, which a computed's Elixir counterpart can't be.
  @callbacks ~w(mount render replay_render handle_event handle_info handle_params handle_call
                handle_cast handle_async terminate code_change)

  # Computeds whose `<script lang="elixir">` counterpart, the function of the
  # same name in snake_case taking the assigns, computes them on the server.
  defp twins(%SFC{setup: setup} = sfc, module) do
    functions = SFC.elixir_functions(sfc)

    for {name, _body} <- setup.computeds,
        function = Macro.underscore(name),
        Map.has_key?(functions, function),
        into: %{} do
      if function in @callbacks do
        raise CompileError,
          file: sfc.file,
          line: 1,
          description:
            "computed `#{name}` can't have an Elixir counterpart: `#{function}` is a LiveView " <>
              "callback. Rename the computed."
      end

      unless MapSet.member?(functions[function], 1) do
        raise CompileError,
          file: sfc.file,
          line: 1,
          description:
            "the Elixir counterpart of computed `#{name}` takes the assigns: define #{function}/1"
      end

      # Rendering skips a counterpart whose required reads are missing.
      reads = SFC.elixir_reads(sfc, function, required: true)
      {name, {module, String.to_existing_atom(function), reads}}
    end
  end

  # The client state a session replay needs: what the template reads, and
  # what the computeds it reads read in turn, an Elixir counterpart's from its
  # patterns. Recording anything else, such as a mouse position, would only
  # flood the recording.
  defp recorded(%SFC{setup: setup} = sfc, split, plan) do
    client = MapSet.new(Map.keys(setup.refs) ++ setup.client_bindings)

    reads = fn name ->
      case plan.reads[name] do
        :any -> SFC.elixir_reads(sfc, Macro.underscore(name))
        keys -> keys || []
      end
    end

    split
    |> Renderer.assign_keys()
    |> Enum.reduce(MapSet.new(), &read(&1, &2, reads))
    |> MapSet.intersection(client)
    |> Enum.sort()
  end

  defp read(name, seen, reads) do
    if MapSet.member?(seen, name),
      do: seen,
      else: name |> reads.() |> Enum.reduce(MapSet.put(seen, name), &read(&1, &2, reads))
  end

  # Top-level constants the server can evaluate once, in order: literals,
  # and expressions of earlier constants and JavaScript's globals, such as
  # `const PAGE_SIZE = 20` or `const roles = ["owner", "admin"]`. Refs,
  # computeds, functions and composables' results aren't constants.
  defp constants(%ScriptSetup{} = setup, runtime) do
    reactive =
      MapSet.new(
        Map.keys(setup.refs) ++
          Map.keys(setup.computeds) ++ setup.callables ++ setup.client_bindings ++ ["props"]
      )

    Enum.reduce(setup.consts, %{}, fn {name, _node, source}, constants ->
      expr = Expr.compile(source)

      if name in reactive or not Enum.all?(Expr.assign_keys(expr), &known?(constants, &1)),
        do: constants,
        else: constant(constants, name, expr, runtime)
    end)
  end

  defp known?(constants, name),
    do: name in Expr.globals() or is_map_key(constants, Names.existing(name))

  defp constant(constants, name, expr, runtime) do
    value = Expr.eval(expr, constants, runtime: runtime)
    Map.put(constants, Names.atom!(name), value)
  rescue
    PhoenixVapor.ExpressionError -> constants
  end

  defp warn_left_out({name, missing}, %SFC{} = sfc) do
    IO.warn(
      "computed `#{name}` reads #{Enum.map_join(missing, ", ", &"`#{&1}`")}, which only the " <>
        "browser has, so the server leaves it, and what reads it, out of the first paint",
      file: Path.relative_to_cwd(sfc.file),
      line: SFC.setup_line(sfc, name)
    )
  end

  # The LiveView assigns a model by its name, which the template and script
  # read by the variable's.
  defp check_models!(%SFC{setup: setup} = sfc) do
    for {name, model} <- setup.models, name != model do
      raise CompileError,
        file: sfc.file,
        line: SFC.setup_line(sfc, name),
        description:
          "the model `#{model}` is bound to `#{name}`: name it after its variable, " <>
            "`const #{name} = defineModel(\"#{name}\")`, the assign the LiveView sets"
    end
  end

  # Props are read-only in Vue, so `props.x = ...` is a mistake, and so is
  # `x = ...` for a prop the script never declares, which fails in the
  # browser. A value the browser changes, and the server owns, is a model. (A
  # destructured prop is a `const`, which JavaScript itself won't let the
  # script write.)
  defp check_prop_writes!(%SFC{setup: %{props: props, source: source}} = sfc) do
    with {:ok, ast} <- OXC.parse(source, "setup.ts"),
         free = MapSet.new(PhoenixVapor.JS.FreeNames.occurrences(ast)),
         [{prop, offset} | _rest] <- prop_writes(ast, props, free) do
      raise CompileError,
        file: sfc.file,
        line: SFC.setup_line_at(sfc, offset),
        description:
          "the prop `#{prop}` is written, but props are read-only. Declare a value the " <>
            "browser changes as a model, `const #{prop} = defineModel(\"#{prop}\")`, and " <>
            "write `#{prop}.value`; see the Hybrid guide's Server actions section"
    else
      _none -> :ok
    end
  end

  # `free` holds each free occurrence of a name with its offset, so a write
  # to a parameter or a local named like a prop isn't one.
  defp prop_writes(ast, props, free) do
    OXC.collect(ast, fn
      %{type: :assignment_expression, left: target} ->
        prop_write(target, props, free)

      %{type: :update_expression, argument: target} ->
        prop_write(target, props, free)

      _node ->
        :skip
    end)
  end

  defp prop_write(
         %{
           type: :member_expression,
           object: %{type: :identifier, name: "props"},
           property: %{name: prop}
         } = target,
         props,
         _free
       ) do
    if prop in props, do: {:keep, {prop, target.start}}, else: :skip
  end

  defp prop_write(%{type: :identifier, name: name, start: start}, props, free) do
    if name in props and MapSet.member?(free, {name, start}),
      do: {:keep, {name, start}},
      else: :skip
  end

  defp prop_write(_target, _props, _free), do: :skip

  # A counterpart that requires state the live render never has, such as a
  # composable's value or a left-out computed, is never called there, so its
  # computed is missing from the first paint; only a replay has the state.
  # Counterparts are in order, so one skipped makes those requiring it
  # skipped too.
  defp warn_skipped_twins(plan, %SFC{setup: setup} = sfc) do
    absent = setup.client_bindings ++ Enum.map(plan.left_out, &elem(&1, 0))

    Enum.reduce(plan.per_render, absent, fn
      {name, {:elixir, _module, function, reads}}, absent ->
        case Enum.filter(reads, &(&1 in absent)) do
          [] ->
            absent

          missing ->
            warn_skipped_twin(name, Atom.to_string(function), missing, sfc)
            [name | absent]
        end

      _computed, absent ->
        absent
    end)
  end

  defp warn_skipped_twin(name, function, missing, sfc) do
    IO.warn(
      "`#{function}/1` requires #{Enum.map_join(missing, ", ", &"`#{&1}`")}, which only the " <>
        "browser has, so the live render never calls it and leaves `#{name}` out of the " <>
        "first paint. Read state that may be missing as `assigns[:#{hd(missing)}]` rather " <>
        "than in a pattern",
      file: Path.relative_to_cwd(sfc.file),
      line: SFC.elixir_line(sfc, function)
    )
  end

  # A computed that fails with the refs' initial values is left to the
  # browser, with a warning.
  # Refs and computeds are read as `.value`; constants as they are.
  defp constant_values(computeds, refs, constants, runtime, file),
    do: Enum.reduce(computeds, refs, &constant_value(&1, &2, constants, runtime, file))

  defp constant_value({name, _expr} = computed, values, constants, runtime, file) do
    assigns = Map.merge(constants, values)
    {values, _assigns} = Computeds.evaluate([computed], values, assigns, runtime: runtime)
    values
  rescue
    error in PhoenixVapor.ExpressionError ->
      IO.warn("computed `#{name}` can't render on the server: #{Exception.message(error)}",
        file: Path.relative_to_cwd(file)
      )

      values
  end

  defp generate_client_js(%SFC{file: full_path} = sfc, classification, recorded, output_dir) do
    codegen_opts = [source_dir: Path.dirname(full_path), output_dir: output_dir, record: recorded]

    case ClientCodegen.generate(sfc.source, classification, codegen_opts) do
      {:ok, js} when is_binary(output_dir) ->
        output_path = Path.join(output_dir, Path.basename(full_path, ".vue") <> ".hybrid.js")
        File.mkdir_p!(output_dir)
        File.write!(output_path, js)
        {js, Path.expand(output_path)}

      {:ok, js} ->
        {js, nil}

      {:error, errors} ->
        raise "Failed to compile client JS for #{full_path}: #{inspect(errors)}"
    end
  end

  defp default_client_output do
    project_root = File.cwd!()
    assets_dir = Path.join(project_root, "assets/js/hybrid")

    if File.dir?(Path.join(project_root, "assets")), do: assets_dir
  end
end
