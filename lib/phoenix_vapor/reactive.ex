defmodule PhoenixVapor.Reactive do
  @moduledoc """
  Server-side Vue reactivity via QuickBEAM.

  Use via: `use PhoenixVapor, file: "X.vue", runtime: :reactive`

  Compiles `<script setup>` + `<template>` from a `.vue` file into a
  fully functional LiveView with auto-generated mount, render, and
  event handlers.

  A persistent `PhoenixVapor.Reactive.Runtime` (QuickBEAM + Vue reactivity) is
  started per LiveView process. `ref()` values become reactive state,
  `computed()` auto-update when deps change, and functions execute in
  the persistent JS context — state survives across events.

  ## Usage

      defmodule MyAppWeb.CounterLive do
        use MyAppWeb, :live_view
        use PhoenixVapor, file: "Counter.vue", runtime: :reactive
      end

  Given `Counter.vue`:

      <script setup>
      import { ref, computed } from "vue"

      const count = ref(0)
      const doubled = computed(() => count * 2)

      function increment() { count++ }
      </script>

      <template>
        <p>{{ count }} × 2 = {{ doubled }}</p>
        <button @click="increment">+</button>
      </template>

  This generates:

  - `mount/3` — starts a `Runtime` with refs, computeds, and functions
  - `render/1` — renders the template, compiled from Vize's split, with the runtime's state
  - `handle_event/3` — calls the function in the runtime, assigns new state
  """

  alias PhoenixVapor.{Compiler, Renderer}
  alias PhoenixVapor.Compiler.SFC
  alias PhoenixVapor.Renderer.Names

  defmacro __using__(opts) do
    opts |> Keyword.fetch!(:file) |> SFC.load!(__CALLER__) |> build()
  end

  @doc false
  # The LiveView for a reactive `.vue` file: `mount/3` starting its runtime,
  # `render/1`, and a `handle_event/3` per function.
  @spec build(SFC.t()) :: Macro.t()
  def build(%SFC{setup: setup} = sfc) do
    # The root element carries the statics for the browser's patcher.
    {split, component_files} = Compiler.compile!(sfc, root_attrs: true)
    escaped_split = Macro.escape(split)
    escaped_metadata = split |> Renderer.vapor_metadata() |> Macro.escape()

    # Only URL params the template reads become assigns, so a request can't
    # create atoms.
    param_keys = split |> Renderer.assign_keys() |> Enum.map(&Names.atom!/1)
    state_keys = Enum.map(Map.keys(setup.refs) ++ Map.keys(setup.computeds), &Names.atom!/1)

    mount_ast = gen_mount(setup, param_keys, state_keys)
    render_ast = gen_render(escaped_split, escaped_metadata)
    event_asts = gen_events(Map.keys(setup.functions), state_keys)

    quote do
      import PhoenixVapor.Sigil
      @external_resource unquote(sfc.file)
      for file <- unquote(component_files), do: @external_resource(file)

      unquote(mount_ast)
      unquote(render_ast)
      unquote_splicing(event_asts)
    end
  end

  defp gen_mount(setup, param_keys, state_keys) do
    escaped_refs = Macro.escape(setup.refs)
    escaped_computeds = Macro.escape(setup.computeds)
    escaped_functions = Macro.escape(setup.functions)

    quote do
      def mount(params, _session, socket) do
        {:ok, runtime} =
          PhoenixVapor.Reactive.Runtime.start_link(
            refs: unquote(escaped_refs),
            computeds: unquote(escaped_computeds),
            functions: unquote(escaped_functions)
          )

        {:ok, state} = PhoenixVapor.Reactive.Runtime.get_state(runtime)
        assigns = PhoenixVapor.Reactive.state_to_assigns(state, unquote(state_keys))

        param_assigns = PhoenixVapor.Reactive.param_assigns(params, unquote(param_keys))

        socket =
          socket
          |> Phoenix.Component.assign(assigns)
          |> Phoenix.Component.assign(param_assigns)
          # Private, so it isn't an assign: render/1 doesn't read it, and a
          # session recorder doesn't record it.
          |> Phoenix.LiveView.put_private(:phoenix_vapor_runtime, runtime)

        {:ok, socket}
      end
    end
  end

  defp gen_render(escaped_split, escaped_metadata) do
    quote do
      def render(var!(assigns)) do
        PhoenixVapor.Renderer.to_rendered(unquote(escaped_split), var!(assigns),
          root_attrs: unquote(escaped_metadata)
        )
      end
    end
  end

  defp gen_events(functions, state_keys) do
    Enum.map(functions, fn func_name ->
      quote do
        def handle_event(unquote(func_name), params, socket) do
          runtime = socket.private.phoenix_vapor_runtime

          {:ok, state} =
            PhoenixVapor.Reactive.Runtime.call_handler(runtime, unquote(func_name), params)

          assigns = PhoenixVapor.Reactive.state_to_assigns(state, unquote(state_keys))
          {:noreply, Phoenix.Component.assign(socket, assigns)}
        end
      end
    end)
  end

  @doc """
  Picks the URL params named by `keys` and returns them as assigns.

  Generated `mount/3` callbacks pass the assign keys their template reads, so
  a param never creates an atom.
  """
  @spec param_assigns(map() | :not_mounted_at_router, [atom()]) :: map()
  def param_assigns(params, keys) when is_map(params) do
    for key <- keys, {:ok, value} <- [Map.fetch(params, Atom.to_string(key))], into: %{} do
      {key, value}
    end
  end

  def param_assigns(_not_mounted_at_router, _keys), do: %{}

  @doc """
  Converts the state a `PhoenixVapor.Reactive.Runtime` returns into assigns.

  `keys` are the ref and computed names declared in the component, as atoms
  created when it compiled.
  """
  @spec state_to_assigns(map(), [atom()]) :: map()
  def state_to_assigns(state, keys) when is_map(state) do
    for key <- keys, {:ok, value} <- [Map.fetch(state, Atom.to_string(key))], into: %{} do
      {key, value}
    end
  end
end
