defmodule PhoenixVapor.VueRuntime do
  @moduledoc """
  Full Vue component runtime in QuickBEAM.

  Mounts a Vue application server-side with the complete component
  runtime — `defineComponent`, `provide/inject`, `onMounted`, render
  functions, slots, and third-party component libraries (Reka UI, etc.).

  Unlike `PhoenixVapor.Runtime` (which uses only `@vue/reactivity`),
  VueRuntime loads the full Vue runtime and renders into QuickBEAM's
  lexbor DOM. The resulting HTML feeds into `%Phoenix.LiveView.Rendered{}`
  for LiveView's diff protocol.

  ## Usage

      {:ok, rt} = VueRuntime.start_link(
        bundle: "priv/js/reka-dialog.js",
        setup: ~s(
          const { createApp, ref, defineComponent, h } = Vue;
          const { DialogRoot, DialogTrigger, DialogContent } = RekaDialog;

          const open = ref(false);
          // ... mount app ...
        )
      )

      {:ok, html} = VueRuntime.render(rt)
      {:ok, html} = VueRuntime.call(rt, "dialogOpen.value = true")
  """

  use GenServer

  # ── Public API ──

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @doc "Get the current DOM HTML."
  def render(runtime), do: GenServer.call(runtime, :render)

  @doc "Evaluate JS (e.g. mutate reactive state), flush Vue updates, return new HTML."
  def call(runtime, js_code), do: GenServer.call(runtime, {:call, js_code})

  @doc "Get current state of all registered refs."
  def get_state(runtime), do: GenServer.call(runtime, :get_state)

  def stop(runtime), do: GenServer.stop(runtime)

  # ── GenServer ──

  @impl true
  def init(opts) do
    bundle = Keyword.fetch!(opts, :bundle)
    setup = Keyword.get(opts, :setup, "")
    pool = Keyword.get(opts, :pool) || Application.get_env(:phoenix_vapor, :pool)

    {js, mode} = start_js(pool)
    state = %{js: js, mode: mode}

    # Combined eval avoids QuickBEAM microtask queue issue
    # where separate evals hang after Vue's reactive mount
    combined = read_bundle(bundle) <> "\n;\n" <> setup

    case js_eval(state, combined) do
      {:ok, _} -> {:ok, state}
      {:error, err} ->
        stop_js(js, mode)
        {:stop, err}
    end
  end

  @impl true
  def handle_call(:render, _from, state) do
    {:reply, js_eval(state, "document.body.innerHTML"), state}
  end

  def handle_call({:call, js_code}, _from, state) do
    # Mutate state — ignore errors (e.g. FocusScope stack overflow in Reka UI)
    js_eval(state, js_code)
    # Vue batches updates via microtask — separate eval flushes the queue
    {:reply, js_eval(state, "document.body.innerHTML"), state}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, js_eval(state, "typeof __pv_getState === 'function' ? __pv_getState() : {}"), state}
  end

  @impl true
  def terminate(_reason, %{js: js, mode: :context}), do: QuickBEAM.Context.stop(js)
  def terminate(_reason, %{js: js, mode: :runtime}), do: QuickBEAM.stop(js)

  # ── JS dispatch ──

  defp js_eval(%{js: js, mode: :context}, code), do: QuickBEAM.Context.eval(js, code)
  defp js_eval(%{js: js, mode: :runtime}, code), do: QuickBEAM.eval(js, code)

  @stack_size 8 * 1024 * 1024

  defp start_js(nil) do
    {:ok, rt} = QuickBEAM.start(apis: [:browser], max_stack_size: @stack_size)
    {rt, :runtime}
  end

  defp start_js(pool) do
    if Code.ensure_loaded?(QuickBEAM.Context) do
      {:ok, ctx} = QuickBEAM.Context.start_link(pool: pool, apis: [:browser], max_stack_size: @stack_size)
      {ctx, :context}
    else
      start_js(nil)
    end
  end

  defp stop_js(js, :context), do: QuickBEAM.Context.stop(js)
  defp stop_js(js, :runtime), do: QuickBEAM.stop(js)

  defp read_bundle(path) when is_binary(path) do
    cond do
      File.regular?(path) -> File.read!(path)
      File.regular?(Path.join(:code.priv_dir(:phoenix_vapor) |> to_string(), path)) ->
        File.read!(Path.join(:code.priv_dir(:phoenix_vapor) |> to_string(), path))
      true -> raise "Bundle not found: #{path}"
    end
  end
end
