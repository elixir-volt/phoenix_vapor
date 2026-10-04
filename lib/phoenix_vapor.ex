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

  alias PhoenixVapor.{Compiler, Renderer}
  alias PhoenixVapor.Compiler.SFC

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

  defp do_use_file(_file, runtime, _opts, _caller) when runtime not in [nil, :reactive] do
    raise ArgumentError,
          "unknown :runtime #{inspect(runtime)}; use :reactive or :full, or leave it out " <>
            "to choose between server-only and hybrid from the component"
  end

  defp do_use_file(file, runtime, opts, caller) do
    sfc = SFC.load!(file, caller)

    cond do
      runtime == :reactive -> PhoenixVapor.Reactive.build(sfc)
      SFC.client_state?(sfc) -> PhoenixVapor.Hybrid.build(sfc, opts, caller)
      true -> server_only(sfc, caller)
    end
  end

  # Without client state, the template renders on the server, and the rest
  # of the LiveView is the module's own Elixir.
  defp server_only(sfc, caller) do
    {split, component_files} = Compiler.compile!(sfc, module: caller.module)
    escaped_split = Macro.escape(split)

    quote do
      import PhoenixVapor.Sigil
      import PhoenixVapor.Component
      @external_resource unquote(sfc.file)
      for file <- unquote(component_files), do: @external_resource(file)

      def render(var!(assigns)) do
        PhoenixVapor.Renderer.to_rendered(unquote(escaped_split), var!(assigns))
      end

      unquote_splicing(sfc.elixir)
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
