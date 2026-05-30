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

  defp do_use_file(file, :full, opts, _caller) do
    bundle = Keyword.fetch!(opts, :bundle)

    quote do
      use PhoenixVapor.LiveVue,
        file: unquote(file),
        bundle: unquote(bundle)
    end
  end

  defp do_use_file(file, :reactive, _opts, _caller) do
    quote do
      use PhoenixVapor.Reactive, file: unquote(file)
    end
  end

  defp do_use_file(file, _runtime, opts, caller) do
    caller_dir = caller.file |> Path.dirname()
    full_path = Path.expand(file, caller_dir)
    sfc_source = File.read!(full_path)

    desc = Vize.parse_sfc!(sfc_source)

    script_content =
      case desc.script_setup do
        %{content: c} -> c
        nil -> ""
      end

    {refs, _computeds, _functions, _function_bodies, _props} =
      PhoenixVapor.ScriptSetup.parse(script_content)

    has_client_state = map_size(refs) > 0

    if has_client_state do
      all_opts = Keyword.put(opts, :file, file)

      quote do
        use PhoenixVapor.Hybrid, unquote(all_opts)
      end
    else
      do_use_server_only(file, desc, caller)
    end
  end

  defp do_use_server_only(file, desc, caller) do
    caller_dir = caller.file |> Path.dirname()
    full_path = Path.expand(file, caller_dir)

    template_content =
      case desc.template do
        %{content: c} -> String.trim(c)
        nil -> raise "No <template> block found in #{file}"
      end

    split = Vize.vapor_split!(template_content)
    escaped_split = Macro.escape(split)

    elixir_block_ast =
      case desc.script do
        %{lang: "elixir", content: content} when is_binary(content) ->
          case Code.string_to_quoted(content, file: full_path) do
            {:ok, {:__block__, _, exprs}} ->
              exprs

            {:ok, expr} ->
              [expr]

            {:error, {meta, msg, token}} ->
              line = Keyword.get(List.wrap(meta), :line, 0)
              raise CompileError, file: full_path, line: line, description: "#{msg}#{token}"
          end

        _ ->
          []
      end

    quote do
      import PhoenixVapor.Sigil
      import PhoenixVapor.Component
      @external_resource unquote(full_path)

      def render(var!(assigns)) do
        PhoenixVapor.Renderer.to_rendered(unquote(escaped_split), var!(assigns))
      end

      unquote_splicing(elixir_block_ast)
    end
  end

  @doc """
  Assigns an advanced hybrid prop under PhoenixVapor's reserved prop storage.

  Values assigned this way take precedence over regular LiveView assigns when a
  hybrid component serializes `defineProps` data.
  """
  @spec assign_prop(
          Phoenix.LiveView.Socket.t(),
          atom() | String.t() | PhoenixVapor.Prop.preserved_key(),
          term()
        ) ::
          Phoenix.LiveView.Socket.t()
  def assign_prop(socket, key, value) do
    props = Map.get(socket.assigns, :__pv_props__, %{})
    Phoenix.Component.assign(socket, :__pv_props__, Map.put(props, key, value))
  end

  @doc """
  Assigns validation errors to a LiveView socket under `:errors`.
  """
  @spec assign_errors(Phoenix.LiveView.Socket.t(), term()) :: Phoenix.LiveView.Socket.t()
  def assign_errors(socket, data) do
    Phoenix.Component.assign(socket, :errors, PhoenixVapor.Errors.to_errors(data))
  end

  @doc """
  Assigns validation errors using a custom changeset message function.
  """
  @spec assign_errors(Phoenix.LiveView.Socket.t(), term(), PhoenixVapor.Errors.msg_func()) ::
          Phoenix.LiveView.Socket.t()
  def assign_errors(socket, data, msg_func) when is_function(msg_func, 1) do
    Phoenix.Component.assign(socket, :errors, PhoenixVapor.Errors.to_errors(data, msg_func))
  end

  @doc """
  Render a Vue template as a `%Phoenix.LiveView.Rendered{}` struct.
  """
  @spec render(String.t() | map(), map()) :: Phoenix.LiveView.Rendered.t()
  def render(template, assigns) when is_binary(template) do
    render(Vize.vapor_split!(template), assigns)
  end

  def render(%{statics: _, slots: _} = split, assigns) do
    Renderer.to_rendered(split, assigns)
  end
end
