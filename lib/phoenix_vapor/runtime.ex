defmodule PhoenixVapor.Runtime do
  @moduledoc """
  Persistent Vue reactive context backed by QuickBEAM.

  Each Runtime holds a QuickBEAM process with Vue's reactivity system loaded.
  `ref()` values become reactive state, `computed()` values auto-update when
  dependencies change, and functions execute in-place against reactive refs.

  State persists across calls — the same reactive graph lives for the lifetime
  of the owning LiveView process.

  ## Context Pool mode

  When a `QuickBEAM.ContextPool` is configured, each Runtime uses a lightweight
  context (~50KB) on a shared thread pool instead of a dedicated OS thread (~2MB).
  This is the recommended mode for production — 10K LiveViews share 4 OS threads
  instead of spawning 10K.

      # In your application supervisor:
      {QuickBEAM.ContextPool, name: MyApp.JSPool, size: 4}

      # In config:
      config :phoenix_vapor, pool: MyApp.JSPool

  Without a pool, each Runtime gets its own `QuickBEAM.Runtime` (full isolation,
  higher resource usage).

  ## Usage

      {:ok, rt} = Runtime.start_link(
        refs: %{"count" => "0"},
        computeds: %{"doubled" => "count * 2"},
        functions: ["increment"],
        function_bodies: %{"increment" => "count++"}
      )

      {:ok, state} = Runtime.get_state(rt)
      {:ok, state} = Runtime.call_handler(rt, "increment", %{})
  """

  use GenServer

  @reactivity_js_path Path.join(:code.priv_dir(:phoenix_vapor), "js/vue-reactivity.js")
  @setup_js_path Path.join(:code.priv_dir(:phoenix_vapor), "js/runtime-setup.js")
  @external_resource @reactivity_js_path
  @external_resource @setup_js_path
  @reactivity_js File.read!(@reactivity_js_path)
  @setup_js File.read!(@setup_js_path)

  # ── Public API ──

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  def get_state(runtime), do: GenServer.call(runtime, :get_state)

  def call_handler(runtime, function_name, params \\ %{}),
    do: GenServer.call(runtime, {:call_handler, function_name, params})

  def set_state(runtime, updates) when is_map(updates),
    do: GenServer.call(runtime, {:set_state, updates})

  # ── GenServer callbacks ──

  @impl true
  def init(opts) do
    pool = Keyword.get(opts, :pool) || Application.get_env(:phoenix_vapor, :pool)

    config = %{
      refs: Keyword.get(opts, :refs, %{}),
      computeds: topo_sort_computeds(Keyword.get(opts, :computeds, %{})),
      functions: build_functions_map(opts)
    }

    case setup_runtime(config, pool) do
      {:ok, js, mode} -> {:ok, %{js: js, mode: mode}}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, js_call(state, "__pv_getState", []), state}
  end

  def handle_call({:call_handler, name, params}, _from, state) do
    {:reply, js_call(state, "__pv_callHandler", [name, params]), state}
  end

  def handle_call({:set_state, updates}, _from, state) do
    {:reply, js_call(state, "__pv_setState", [updates]), state}
  end

  @impl true
  def terminate(_reason, %{js: js, mode: :context}), do: QuickBEAM.Context.stop(js)
  def terminate(_reason, %{js: js, mode: :runtime}), do: QuickBEAM.stop(js)

  # ── JS dispatch ──

  defp js_eval(%{js: js, mode: :context}, code), do: QuickBEAM.Context.eval(js, code)
  defp js_eval(%{js: js, mode: :runtime}, code), do: QuickBEAM.eval(js, code)

  defp js_call(%{js: js, mode: :context}, f, a), do: QuickBEAM.Context.call(js, f, a)
  defp js_call(%{js: js, mode: :runtime}, f, a), do: QuickBEAM.call(js, f, a)

  # ── Setup ──

  defp setup_runtime(config, pool) do
    {js, mode} = start_js(pool)
    state = %{js: js, mode: mode}

    with {:ok, _} <- js_eval(state, @reactivity_js),
         {:ok, _} <- js_eval(state, @setup_js),
         {:ok, _} <- js_call(state, "__pv_setup", [config]) do
      {:ok, js, mode}
    else
      {:error, err} ->
        stop_js(js, mode)
        {:error, err}
    end
  end

  defp start_js(nil) do
    {:ok, rt} = QuickBEAM.start()
    {rt, :runtime}
  end

  defp start_js(pool) do
    if Code.ensure_loaded?(QuickBEAM.Context) do
      {:ok, ctx} = QuickBEAM.Context.start_link(pool: pool, apis: false)
      {ctx, :context}
    else
      start_js(nil)
    end
  end

  defp stop_js(js, :context), do: QuickBEAM.Context.stop(js)
  defp stop_js(js, :runtime), do: QuickBEAM.stop(js)

  # ── Config helpers ──

  defp build_functions_map(opts) do
    bodies = Keyword.get(opts, :function_bodies, %{})

    Keyword.get(opts, :functions, [])
    |> Map.new(fn name -> {name, Map.get(bodies, name, "")} end)
  end

  defp topo_sort_computeds(computeds) when map_size(computeds) <= 1, do: computeds

  defp topo_sort_computeds(computeds) do
    names = Map.keys(computeds)

    deps =
      Map.new(computeds, fn {name, expr} ->
        referenced = Enum.filter(names, &(&1 != name && Regex.match?(~r/\b#{Regex.escape(&1)}\b/, expr)))
        {name, referenced}
      end)

    {sorted, _} =
      Enum.reduce(names, {[], MapSet.new()}, fn _, {acc, visited} ->
        case Enum.find(names, fn n -> n not in visited && Enum.all?(deps[n] || [], &(&1 in visited)) end) do
          nil -> {acc, visited}
          name -> {acc ++ [{name, computeds[name]}], MapSet.put(visited, name)}
        end
      end)

    Map.new(sorted)
  end
end
