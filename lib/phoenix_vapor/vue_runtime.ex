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
  """

  use GenServer

  @stack_size 16 * 1024 * 1024

  # ── Public API ──

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @doc "Get the current DOM HTML."
  def render(runtime), do: GenServer.call(runtime, :render)

  @doc "Dispatch a named event to __pv_handlers, return updated HTML."
  def dispatch(runtime, event, params \\ %{}),
    do: GenServer.call(runtime, {:dispatch, event, params})

  @doc "Evaluate arbitrary JS, flush Vue updates, return new HTML."
  def call(runtime, js_code), do: GenServer.call(runtime, {:call, js_code})

  def stop(runtime), do: GenServer.stop(runtime)

  # ── GenServer ──

  @impl true
  def init(opts) do
    bundle = Keyword.fetch!(opts, :bundle)
    setup = Keyword.get(opts, :setup, "")
    pool = Keyword.get(opts, :pool) || Application.get_env(:phoenix_vapor, :pool)

    {js, mode} = start_js(pool)
    state = %{js: js, mode: mode}

    combined = read_bundle(bundle) <> "\n;\n(function(){\n" <> setup <> "\n})();"

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

  def handle_call({:dispatch, event, params}, _from, state) do
    js_eval(state, dispatch_js(event, params))
    {:reply, js_eval(state, "document.body.innerHTML"), state}
  end

  def handle_call({:call, js_code}, _from, state) do
    js_eval(state, js_code)
    {:reply, js_eval(state, "document.body.innerHTML"), state}
  end

  @impl true
  def terminate(_reason, %{js: js, mode: :context}), do: QuickBEAM.Context.stop(js)
  def terminate(_reason, %{js: js, mode: :runtime}), do: QuickBEAM.stop(js)

  # ── Private ──

  defp dispatch_js(event, params) do
    encoded = Jason.encode!(params)
    # Safe dispatch — event name looked up as object key, not interpolated into code
    """
    (function() {
      var h = typeof __pv_handlers !== 'undefined' && __pv_handlers;
      if (h) {
        var fn = h[arguments[0]];
        if (fn) fn(JSON.parse(arguments[1]));
      }
    })(#{Jason.encode!(event)}, #{Jason.encode!(encoded)})
    """
  end

  defp js_eval(%{js: js, mode: :context}, code), do: QuickBEAM.Context.eval(js, code)
  defp js_eval(%{js: js, mode: :runtime}, code), do: QuickBEAM.eval(js, code)

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
    expanded = Path.expand(path)

    cond do
      File.regular?(expanded) ->
        File.read!(expanded)

      File.regular?(Path.join(to_string(:code.priv_dir(:phoenix_vapor)), path)) ->
        File.read!(Path.join(to_string(:code.priv_dir(:phoenix_vapor)), path))

      true ->
        raise "Bundle not found: #{path}"
    end
  end
end
