defmodule PhoenixVapor.Reactive do
  @moduledoc """
  Use Vue Single File Components as LiveView modules.

  Compiles `<script setup>` + `<template>` from a `.vue` file into a
  fully functional LiveView with auto-generated mount, render, and
  event handlers.

  ## Usage

      defmodule MyAppWeb.CounterLive do
        use MyAppWeb, :live_view
        use PhoenixVapor.Reactive, file: "lib/my_app_web/live/Counter.vue"
      end

  Given `Counter.vue`:

      <script setup>
      import { ref, computed } from "vue"

      defineProps(["title"])

      const count = ref(0)
      const doubled = computed(() => count * 2)

      function increment() {
        count++
      }
      </script>

      <template>
        <div>
          <h1>{{ title }}</h1>
          <p>{{ count }} (doubled: {{ doubled }})</p>
          <button @click="increment">+</button>
        </div>
      </template>

  This generates:

  - `mount/3` — initializes assigns from `ref()` values
  - `render/1` — renders the template via `~VUE` / Vapor IR
  - `handle_event/3` — one clause per function in `<script setup>`,
    evaluates the function body in QuickBEAM against current assigns,
    then updates assigns with the new state
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

    ir = Vize.vapor_ir!(template_content)
    escaped_ir = Macro.escape(ir)

    {refs, computeds, functions, props} =
      if script_content do
        PhoenixVapor.ScriptSetup.parse(script_content)
      else
        {%{}, %{}, [], []}
      end

    # Build event handler function bodies from the original script
    function_bodies = extract_function_bodies(script_content || "", functions)

    # Generate the module code
    mount_ast = gen_mount(refs, computeds, props)
    render_ast = gen_render(escaped_ir, computeds)
    event_asts = gen_events(functions, function_bodies, refs, computeds)

    quote do
      import PhoenixVapor.Sigil

      unquote(mount_ast)
      unquote(render_ast)
      unquote_splicing(event_asts)
    end
  end

  defp gen_mount(refs, computeds, _props) do
    ref_pairs =
      Enum.map(refs, fn {name, init_expr} ->
        {String.to_atom(name), init_expr}
      end)

    computed_exprs = Map.to_list(computeds)

    quote do
      def mount(params, _session, socket) do
        initial =
          unquote(Macro.escape(ref_pairs))
          |> Enum.reduce(%{}, fn {name, init_expr}, acc ->
            value =
              case init_expr do
                "0" -> 0
                "\"" <> _ -> init_expr |> Code.eval_string() |> elem(0)
                "true" -> true
                "false" -> false
                "null" -> nil
                "[]" -> []
                "{}" -> %{}
                expr -> PhoenixVapor.Expr.eval(expr, %{}) || 0
              end

            Map.put(acc, name, value)
          end)

        socket = Phoenix.Component.assign(socket, initial)

        # Merge URL params as assigns
        param_assigns =
          params
          |> Enum.reduce(%{}, fn {k, v}, acc ->
            Map.put(acc, String.to_atom(k), v)
          end)

        socket = Phoenix.Component.assign(socket, param_assigns)

        # Evaluate computeds
        computed_assigns =
          unquote(Macro.escape(computed_exprs))
          |> Enum.reduce(%{}, fn {name, expr}, acc ->
            value = PhoenixVapor.Expr.eval(expr, socket.assigns)
            Map.put(acc, String.to_atom(name), value)
          end)

        {:ok, Phoenix.Component.assign(socket, computed_assigns)}
      end
    end
  end

  defp gen_render(escaped_ir, computeds) do
    computed_exprs = Map.to_list(computeds)

    quote do
      def render(var!(assigns)) do
        # Re-evaluate computeds before rendering
        var!(assigns) =
          unquote(Macro.escape(computed_exprs))
          |> Enum.reduce(var!(assigns), fn {name, expr}, acc ->
            value = PhoenixVapor.Expr.eval(expr, acc)
            Map.put(acc, String.to_atom(name), value)
          end)

        PhoenixVapor.Renderer.to_rendered(unquote(escaped_ir), var!(assigns), vapor_metadata: true)
      end
    end
  end

  defp gen_events(functions, function_bodies, refs, computeds) do
    ref_names = Map.keys(refs)
    computed_exprs = Map.to_list(computeds)

    Enum.map(functions, fn func_name ->
      body = Map.get(function_bodies, func_name, "")

      quote do
        def handle_event(unquote(func_name), params, socket) do
          current =
            unquote(Macro.escape(ref_names))
            |> Enum.reduce(%{}, fn name, acc ->
              atom = String.to_atom(name)
              Map.put(acc, name, Map.get(socket.assigns, atom))
            end)

          new_state = PhoenixVapor.Reactive.eval_handler(unquote(body), current, params)

          ref_assigns =
            Enum.reduce(new_state, %{}, fn {k, v}, acc ->
              Map.put(acc, String.to_atom(k), v)
            end)

          socket = Phoenix.Component.assign(socket, ref_assigns)

          # Re-evaluate computeds
          computed_assigns =
            unquote(Macro.escape(computed_exprs))
            |> Enum.reduce(%{}, fn {name, expr}, acc ->
              value = PhoenixVapor.Expr.eval(expr, socket.assigns)
              Map.put(acc, String.to_atom(name), value)
            end)

          {:noreply, Phoenix.Component.assign(socket, computed_assigns)}
        end
      end
    end)
  end

  @doc false
  def eval_handler(body, current_state, _params) do
    if Code.ensure_loaded?(QuickBEAM) do
      {:ok, rt} = QuickBEAM.start()

      return_expr =
        current_state
        |> Map.keys()
        |> Enum.map(fn k -> "\"#{k}\": #{k}" end)
        |> Enum.join(", ")

      code = "#{body};\n({#{return_expr}})"

      case QuickBEAM.eval(rt, code, vars: current_state) do
        {:ok, result} when is_map(result) -> result
        _ -> current_state
      end
    else
      current_state
    end
  end

  @doc false
  def extract_function_bodies(script, function_names) do
    Enum.reduce(function_names, %{}, fn name, acc ->
      pattern = ~r/function\s+#{Regex.escape(name)}\s*\([^)]*\)\s*\{/
      case Regex.run(pattern, script, return: :index) do
        [{start_pos, match_len}] ->
          after_brace = start_pos + match_len
          body = extract_brace_body(script, after_brace)
          Map.put(acc, name, body)

        _ ->
          acc
      end
    end)
  end

  defp extract_brace_body(source, start_pos) do
    source
    |> String.slice(start_pos..-1//1)
    |> scan_braces(0, [])
    |> IO.iodata_to_binary()
    |> String.trim()
  end

  defp scan_braces("", _depth, acc), do: Enum.reverse(acc)
  defp scan_braces("}" <> _rest, 0, acc), do: Enum.reverse(acc)
  defp scan_braces("}" <> rest, depth, acc), do: scan_braces(rest, depth - 1, ["}" | acc])
  defp scan_braces("{" <> rest, depth, acc), do: scan_braces(rest, depth + 1, ["{" | acc])
  defp scan_braces(<<c::utf8, rest::binary>>, depth, acc),
    do: scan_braces(rest, depth, [<<c::utf8>> | acc])
end
