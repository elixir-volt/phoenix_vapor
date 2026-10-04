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
  alias PhoenixVapor.Compiler.{ScriptSetup, SFC}
  alias PhoenixVapor.Hybrid.{Classifier, ClientCodegen, ServerCodegen}
  alias PhoenixVapor.JS.Session

  defmacro __using__(opts) do
    opts |> Keyword.fetch!(:file) |> SFC.load!(__CALLER__) |> build(opts, __CALLER__)
  end

  @doc false
  # The LiveView for a hybrid `.vue` file: `render/1`, `handle_event/3`
  # stubs, and its client module.
  @spec build(SFC.t(), keyword(), Macro.Env.t()) :: Macro.t()
  def build(%SFC{} = sfc, opts, caller) do
    {split, component_files} =
      Compiler.compile!(sfc, target: :browser, module: caller.module)

    classification = Classifier.classify(sfc.setup, Renderer.assign_keys(split))
    component_name = Path.basename(sfc.file, ".vue")

    # Ref initializers don't depend on assigns, so they're evaluated once here.
    ref_values =
      Session.with_session(
        &ScriptSetup.eval_initial_state(ref_defaults(classification), Session.runtime(&1))
      )

    render_ast =
      ServerCodegen.gen_render(split, classification,
        computeds: sfc.setup.computeds,
        component: component_name,
        ref_values: ref_values
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

  defp ref_defaults(%{bindings: bindings}) do
    for {name, {:client_ref, init}} <- bindings, into: %{}, do: {name, init}
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
