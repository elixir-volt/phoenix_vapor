defmodule PhoenixVapor do
  @moduledoc """
  Vue templates as native LiveView rendered structs.

  ## Usage

  ### Sigil — Vue syntax in any LiveView

      use PhoenixVapor

      def render(assigns) do
        ~VUE\"""
        <div>{{ count }}</div>
        \"""
      end

  ### SFC — `.vue` file as a LiveView

      use PhoenixVapor, file: "Contacts.vue"

  The compiler reads the `.vue` file and auto-detects the mode:

  - **No `<script setup>`** — pure server template, zero client JS
  - **`<script setup>` with only `defineProps`** — pure server, zero client JS
  - **`<script setup>` with `ref()`** — hybrid mode, Vue 3 on the client
  - **`runtime: :full`** — full Vue runtime in QuickBEAM (for component libraries)

  ### Single-file Elixir

  Embed Elixir code in the `.vue` file with `<script lang="elixir">`:

      <script lang="elixir">
      def mount(_params, _session, socket) do
        {:ok, assign(socket, items: Repo.all(Item))}
      end
      </script>

      <script setup>
      const props = defineProps(["items"])
      const search = ref("")
      </script>

      <template>
        <input v-model="search" />
        <div v-for="item in filtered">{{ item.name }}</div>
      </template>

  ## Programmatic

      PhoenixVapor.render("<div>{{ msg }}</div>", %{msg: "Hello"})
  """

  alias PhoenixVapor.Renderer

  defmacro __using__(opts) do
    case Keyword.get(opts, :file) do
      nil ->
        quote do
          import PhoenixVapor.Sigil
          import PhoenixVapor.Component
        end

      file ->
        runtime = Keyword.get(opts, :runtime)
        do_use_file(file, runtime, opts, __CALLER__)
    end
  end

  defp do_use_file(_file, :full, opts, _caller) do
    quote do
      use PhoenixVapor.Full, unquote(opts)
    end
  end

  defp do_use_file(file, :reactive, _opts, _caller) do
    quote do
      use PhoenixVapor.Reactive, file: unquote(file)
    end
  end

  defp do_use_file(_file, runtime, _opts, _caller) when runtime != nil do
    raise ArgumentError,
          "unknown :runtime #{inspect(runtime)}; use :reactive or :full, or leave it out " <>
            "to choose between server-only and hybrid from the component"
  end

  defp do_use_file(file, nil, opts, caller) do
    full_path = PhoenixVapor.Compiler.SFC.path!(file, caller)
    sfc_source = File.read!(full_path)

    desc = Vize.parse_sfc!(sfc_source)

    script_content =
      case desc.script_setup do
        %{content: c} -> c
        nil -> ""
      end

    {refs, _computeds, _functions, _function_bodies, _props} =
      PhoenixVapor.Compiler.ScriptSetup.parse(script_content)

    has_client_state = map_size(refs) > 0

    if has_client_state do
      all_opts = Keyword.put(opts, :file, full_path)

      quote do
        use PhoenixVapor.Hybrid, unquote(all_opts)
      end
    else
      do_use_server_only(full_path, desc, caller)
    end
  end

  defp do_use_server_only(full_path, desc, caller) do
    {template_content, origin} = PhoenixVapor.Compiler.SFC.template!(desc, full_path)

    script_content =
      case desc.script_setup do
        %{content: c} -> c
        nil -> ""
      end

    {split, component_files} =
      PhoenixVapor.Compiler.compile!(template_content,
        file: full_path,
        origin: origin,
        script: script_content,
        elixir: {caller.module, PhoenixVapor.Compiler.SFC.elixir_functions(desc, full_path)},
        unrendered: :raise
      )

    escaped_split = Macro.escape(split)

    elixir_block_ast = PhoenixVapor.Compiler.SFC.elixir_block(desc, full_path)

    quote do
      import PhoenixVapor.Sigil
      import PhoenixVapor.Component
      @external_resource unquote(full_path)
      for file <- unquote(component_files), do: @external_resource(file)

      def render(var!(assigns)) do
        PhoenixVapor.Renderer.to_rendered(unquote(escaped_split), var!(assigns))
      end

      unquote_splicing(elixir_block_ast)
    end
  end

  @doc """
  Render a Vue template as a `%Phoenix.LiveView.Rendered{}` struct.
  """
  @spec render(String.t() | PhoenixVapor.Template.t(), map()) :: Phoenix.LiveView.Rendered.t()
  def render(template, assigns) when is_binary(template) do
    template |> Vize.split_template!() |> PhoenixVapor.Compiler.Split.compile() |> render(assigns)
  end

  def render(%PhoenixVapor.Template{} = template, assigns) do
    Renderer.to_rendered(template, assigns)
  end
end
