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

    render_ast = ServerCodegen.gen_render(split, classification, props, computeds)
    event_asts = ServerCodegen.gen_handle_events(classification)

    client_js = generate_client_js(sfc_source, classification, full_path, opts)

    escaped_classification = Macro.escape(classification)
    escaped_client_js = Macro.escape(client_js)

    quote do
      @__hybrid_classification__ unquote(escaped_classification)
      @__hybrid_client_js__ unquote(escaped_client_js)
      @external_resource unquote(full_path)

      import PhoenixVapor.Sigil

      unquote(render_ast)
      unquote_splicing(event_asts)

      @doc false
      def __hybrid_client_js__, do: @__hybrid_client_js__

      @doc false
      def __hybrid_classification__, do: @__hybrid_classification__
    end
  end

  defp generate_client_js(sfc_source, classification, full_path, opts) do
    case ClientCodegen.generate(sfc_source, classification) do
      {:ok, js} ->
        maybe_write_client_js(js, full_path, opts)
        js

      {:error, errors} ->
        raise "Failed to compile client JS for #{full_path}: #{inspect(errors)}"
    end
  end

  defp maybe_write_client_js(js, full_path, opts) do
    output_dir = Keyword.get(opts, :client_output, nil)

    if output_dir do
      basename = Path.basename(full_path, ".vue")
      output_path = Path.join(output_dir, "#{basename}.hybrid.js")
      File.mkdir_p!(Path.dirname(output_path))
      File.write!(output_path, js)
    end
  end
end
