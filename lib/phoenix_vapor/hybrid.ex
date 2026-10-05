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

  defmacro __using__(opts) do
    opts |> Keyword.fetch!(:file) |> SFC.load!(__CALLER__) |> build(opts, __CALLER__)
  end

  @doc false
  # The LiveView for a hybrid `.vue` file: `render/1`, `handle_event/3`
  # stubs, and its client module.
  @spec build(SFC.t(), keyword(), Macro.Env.t()) :: Macro.t()
  def build(%SFC{} = sfc, opts, caller) do
    %{constant: constant, per_render: per_render, left_out: left_out} =
      Computeds.compile(sfc.setup)

    Enum.each(left_out, &warn_left_out(&1, sfc.file))

    # The browser's first render uses the refs' initial values, and the
    # computeds of only those, so they're evaluated once here, and package
    # components render with them.
    {split, component_files, values} =
      Session.with_session(PropTypes.handlers(), fn session ->
        runtime = Session.runtime(session)
        refs = ScriptSetup.eval_initial_state(sfc.setup.refs, runtime)
        values = constant_values(constant, refs, runtime, sfc.file)
        known = Map.new(values, fn {key, value} -> {Atom.to_string(key), value} end)

        {split, files} =
          Compiler.compile!(sfc,
            target: :browser,
            module: caller.module,
            session: session,
            known: known,
            browser_only: Enum.map(left_out, &elem(&1, 0))
          )

        {split, files, values}
      end)

    classification = Classifier.classify(sfc.setup, Renderer.assign_keys(split))
    component_name = Path.basename(sfc.file, ".vue")

    render_ast =
      ServerCodegen.gen_render(split, classification,
        values: values,
        constant: constant,
        computeds: per_render,
        component: component_name
      )

    event_asts = ServerCodegen.gen_handle_events(classification)

    client_output_dir = Keyword.get(opts, :client_output, default_client_output())
    client_js = generate_client_js(sfc, classification, client_output_dir)

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
    end
  end

  defp warn_left_out({name, missing}, file) do
    IO.warn(
      "computed `#{name}` reads #{Enum.map_join(missing, ", ", &"`#{&1}`")}, which only the " <>
        "browser has, so the server leaves it, and what reads it, out of the first paint",
      file: Path.relative_to_cwd(file)
    )
  end

  # A computed that fails with the refs' initial values is left to the
  # browser, with a warning.
  defp constant_values(computeds, refs, runtime, file),
    do: Enum.reduce(computeds, refs, &constant_value(&1, &2, runtime, file))

  defp constant_value({name, _expr} = computed, values, runtime, file) do
    {values, _assigns} = Computeds.evaluate([computed], values, values, runtime: runtime)
    values
  rescue
    error in PhoenixVapor.ExpressionError ->
      IO.warn("computed `#{name}` can't render on the server: #{Exception.message(error)}",
        file: Path.relative_to_cwd(file)
      )

      values
  end

  defp generate_client_js(%SFC{file: full_path} = sfc, classification, output_dir) do
    codegen_opts = [source_dir: Path.dirname(full_path), output_dir: output_dir]

    case ClientCodegen.generate(sfc.source, classification, codegen_opts) do
      {:ok, js} ->
        if output_dir do
          basename = Path.basename(full_path, ".vue")
          output_path = Path.join(output_dir, "#{basename}.hybrid.js")
          File.mkdir_p!(output_dir)
          File.write!(output_path, js)
        end

        js

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
