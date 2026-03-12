defmodule PhoenixVapor.Reactive do
  @moduledoc """
  Use Vue Single File Components as LiveView modules.

  Compiles `<script setup>` + `<template>` from a `.vue` file into a
  fully functional LiveView with auto-generated mount, render, and
  event handlers.

  A persistent `PhoenixVapor.Runtime` (QuickBEAM + Vue reactivity) is
  started per LiveView process. `ref()` values become reactive state,
  `computed()` auto-update when deps change, and functions execute in
  the persistent JS context — state survives across events.

  ## Usage

      defmodule MyAppWeb.CounterLive do
        use MyAppWeb, :live_view
        use PhoenixVapor.Reactive, file: "Counter.vue"
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
  - `render/1` — reads state from runtime, renders via Vapor split
  - `handle_event/3` — calls the function in the runtime, assigns new state
  """

  defmacro __using__(opts) do
    file = Keyword.fetch!(opts, :file)
    caller_dir = __CALLER__.file |> Path.dirname()
    full_path = Path.expand(file, caller_dir)
    source = File.read!(full_path)

    desc = Vize.parse_sfc!(source)

    template_content =
      case desc.template do
        %{content: c} -> String.trim(c)
        nil -> raise "No <template> block found in #{file}"
      end

    script_content =
      case desc.script_setup do
        %{content: c} -> c
        nil -> nil
      end

    split = Vize.vapor_split!(template_content)
    escaped_split = Macro.escape(split)

    {refs, computeds, functions, function_bodies, props} =
      if script_content do
        PhoenixVapor.ScriptSetup.parse(script_content)
      else
        {%{}, %{}, [], %{}, []}
      end

    mount_ast = gen_mount(refs, computeds, functions, function_bodies, props)
    render_ast = gen_render(escaped_split)
    event_asts = gen_events(functions)

    quote do
      import PhoenixVapor.Sigil

      unquote(mount_ast)
      unquote(render_ast)
      unquote_splicing(event_asts)
    end
  end

  defp gen_mount(refs, computeds, functions, function_bodies, _props) do
    escaped_refs = Macro.escape(refs)
    escaped_computeds = Macro.escape(computeds)
    escaped_functions = Macro.escape(functions)
    escaped_function_bodies = Macro.escape(function_bodies)

    quote do
      def mount(params, _session, socket) do
        {:ok, runtime} =
          PhoenixVapor.Runtime.start_link(
            refs: unquote(escaped_refs),
            computeds: unquote(escaped_computeds),
            functions: unquote(escaped_functions),
            function_bodies: unquote(escaped_function_bodies)
          )

        {:ok, state} = PhoenixVapor.Runtime.get_state(runtime)
        assigns = PhoenixVapor.Reactive.state_to_assigns(state)

        param_assigns =
          Enum.reduce(params, %{}, fn {k, v}, acc ->
            Map.put(acc, String.to_atom(k), v)
          end)

        socket =
          socket
          |> Phoenix.Component.assign(assigns)
          |> Phoenix.Component.assign(param_assigns)
          |> Phoenix.Component.assign(:__vapor_runtime__, runtime)

        {:ok, socket}
      end
    end
  end

  defp gen_render(escaped_split) do
    quote do
      def render(var!(assigns)) do
        PhoenixVapor.Renderer.to_rendered(
          unquote(escaped_split),
          var!(assigns),
          vapor_metadata: true
        )
      end
    end
  end

  defp gen_events(functions) do
    Enum.map(functions, fn func_name ->
      quote do
        def handle_event(unquote(func_name), params, socket) do
          runtime = socket.assigns.__vapor_runtime__

          {:ok, state} =
            PhoenixVapor.Runtime.call_handler(runtime, unquote(func_name), params)

          assigns = PhoenixVapor.Reactive.state_to_assigns(state)
          {:noreply, Phoenix.Component.assign(socket, assigns)}
        end
      end
    end)
  end

  @doc false
  def state_to_assigns(state) when is_map(state) do
    Enum.reduce(state, %{}, fn {k, v}, acc ->
      Map.put(acc, String.to_atom(k), v)
    end)
  end
end
