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

  alias PhoenixVapor.JS

  @stack_size 16 * 1024 * 1024

  # ── Public API ──

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @doc "Get the current DOM HTML."
  def render(runtime), do: GenServer.call(runtime, :render)

  @doc "Dispatch a named event to __pv_handlers, returning updated HTML or its evaluation error."
  def dispatch(runtime, event, params \\ %{}),
    do: GenServer.call(runtime, {:dispatch, event, params})

  @doc "Evaluate arbitrary JS and return new HTML, or the evaluation error if execution fails."
  def call(runtime, js_code), do: GenServer.call(runtime, {:call, js_code})

  def stop(runtime), do: GenServer.stop(runtime)

  # ── GenServer ──

  @impl true
  def init(opts) do
    bundle = Keyword.fetch!(opts, :bundle)
    setup = Keyword.get(opts, :setup, "")
    pool = Keyword.get(opts, :pool) || Application.get_env(:phoenix_vapor, :pool)

    combined = read_bundle(bundle) <> "\n;\n(function(){\n" <> setup <> "\n})();"

    with {:ok, js} <- JS.start(pool, apis: [:browser], max_stack_size: @stack_size) do
      case JS.eval(js, combined) do
        {:ok, _} ->
          {:ok, %{js: js}}

        {:error, err} ->
          JS.stop(js)
          {:stop, err}
      end
    end
  end

  @impl true
  def handle_call(:render, _from, state) do
    {:reply, JS.eval(state.js, "document.body.innerHTML"), state}
  end

  def handle_call({:dispatch, event, params}, _from, state) do
    {:reply, eval_and_render(state, dispatch_js(event, params)), state}
  end

  def handle_call({:call, js_code}, _from, state) do
    {:reply, eval_and_render(state, js_code), state}
  end

  @impl true
  def terminate(_reason, %{js: js}), do: JS.stop(js)

  # ── Private ──

  defp eval_and_render(state, code) do
    with {:ok, _} <- JS.eval(state.js, code) do
      JS.eval(state.js, "document.body.innerHTML")
    end
  end

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

  defp read_bundle(path) when is_binary(path) do
    case File.read(Path.expand(path)) do
      {:ok, source} -> source
      {:error, reason} -> raise "could not read bundle #{path}: #{:file.format_error(reason)}"
    end
  end
end
