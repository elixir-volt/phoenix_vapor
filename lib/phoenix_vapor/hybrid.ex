defmodule PhoenixVapor.Hybrid do
  @moduledoc """
  Use Vue SFCs as hybrid LiveView components with split reactivity.

  Server-owned state (from `defineProps`) is managed by LiveView assigns.
  Client-owned state (`ref()`) runs in the browser via Vue Vapor.
  The compiler automatically classifies bindings and generates both sides.

  ## Usage

      defmodule MyAppWeb.UsersLive do
        use MyAppWeb, :live_view
        use PhoenixVapor.Hybrid, file: "Users.vue"
      end

  Given `Users.vue`:

      <script setup>
      import { ref, computed } from "vue"
      defineProps(["users"])
      const search = ref("")
      const filtered = computed(() => users.filter(u => u.name.includes(search.value)))
      function deleteUser(id) { "use server"; users = users.filter(u => u.id !== id) }
      </script>

      <template>
        <input v-model="search" />
        <p>{{ filtered.length }} results</p>
        <button @click="deleteUser(1)">Delete</button>
      </template>

  This generates:
  - `render/1` — server-rendered HTML with props payload for client hydration
  - `handle_event/3` — for each `"use server"` function
  - A client JS module (Vue Vapor) — written to the build output directory
  """

  alias PhoenixVapor.Hybrid.{Classifier, ServerCodegen, ClientCodegen}

  defmacro __using__(opts) do
    file = Keyword.fetch!(opts, :file)
    caller_dir = __CALLER__.file |> Path.dirname()
    full_path = Path.expand(file, caller_dir)
    sfc_source = File.read!(full_path)

    desc = Vize.parse_sfc!(sfc_source)

    script_content =
      case desc.script_setup do
        %{content: c} -> c
        nil -> ""
      end

    template_content =
      case desc.template do
        %{content: c} -> String.trim(c)
        nil -> raise "No <template> block found in #{file}"
      end

    {refs, computeds, functions, function_bodies, props} =
      PhoenixVapor.ScriptSetup.parse(script_content)

    classification =
      Classifier.classify(refs, computeds, functions, function_bodies, props)

    split = Vize.vapor_split!(template_content)

    component_name = Path.basename(file, ".vue")
    render_ast = ServerCodegen.gen_render(split, classification, props, computeds, component_name)
    event_asts = ServerCodegen.gen_handle_events(classification)

    client_output_dir = Keyword.get(opts, :client_output, default_client_output(caller_dir))
    client_js = generate_client_js(sfc_source, classification, full_path, client_output_dir)

    elixir_block_ast = extract_elixir_block(desc, full_path)

    escaped_classification = Macro.escape(classification)
    escaped_client_js = Macro.escape(client_js)

    quote do
      @__hybrid_classification__ unquote(escaped_classification)
      @__hybrid_client_js__ unquote(escaped_client_js)
      @external_resource unquote(full_path)

      import PhoenixVapor.Sigil

      unquote(render_ast)
      unquote_splicing(event_asts)
      unquote_splicing(elixir_block_ast)

      @doc false
      def __hybrid_client_js__, do: @__hybrid_client_js__

      @doc false
      def __hybrid_classification__, do: @__hybrid_classification__
    end
  end

  defp generate_client_js(sfc_source, classification, full_path, output_dir) do
    case ClientCodegen.generate(sfc_source, classification) do
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

  defp default_client_output(_caller_dir) do
    project_root = File.cwd!()
    assets_dir = Path.join(project_root, "assets/js/hybrid")

    if File.dir?(Path.join(project_root, "assets")), do: assets_dir
  end

  defp extract_elixir_block(desc, file_path) do
    case desc.script do
      %{lang: "elixir", content: content} when is_binary(content) ->
        case Code.string_to_quoted(content, file: file_path) do
          {:ok, {:__block__, _, exprs}} -> exprs
          {:ok, expr} -> [expr]
          {:error, {meta, msg, token}} ->
            line = Keyword.get(List.wrap(meta), :line, 0)
            raise CompileError,
              file: file_path,
              line: line,
              description: "#{msg}#{token}"
        end

      _ ->
        []
    end
  end
end
