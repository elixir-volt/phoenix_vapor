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

  Without a pool, each Runtime gets its own QuickBEAM runtime (full isolation,
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

  alias PhoenixVapor.JS

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
      computeds: Keyword.get(opts, :computeds, %{}),
      functions: build_functions_map(opts)
    }

    case setup_runtime(config, pool) do
      {:ok, js} -> {:ok, %{js: js}}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, JS.call(state.js, "__pv_getState", []), state}
  end

  def handle_call({:call_handler, name, params}, _from, state) do
    {:reply, JS.call(state.js, "__pv_callHandler", [name, params]), state}
  end

  def handle_call({:set_state, updates}, _from, state) do
    {:reply, JS.call(state.js, "__pv_setState", [updates]), state}
  end

  @impl true
  def terminate(_reason, %{js: js}), do: JS.stop(js)

  # ── Setup ──

  defp setup_runtime(config, pool) do
    with {:ok, js} <- JS.start(pool, apis: false) do
      with {:ok, _} <- JS.eval(js, @reactivity_js),
           {:ok, _} <- JS.eval(js, @setup_js),
           {:ok, _} <- JS.call(js, "__pv_setup", [config]) do
        {:ok, js}
      else
        {:error, _} = error ->
          JS.stop(js)
          error
      end
    end
  end

  # ── Config helpers ──

  defp build_functions_map(opts) do
    bodies = Keyword.get(opts, :function_bodies, %{})

    Keyword.get(opts, :functions, [])
    |> Map.new(fn name -> {name, Map.get(bodies, name, "")} end)
  end
end
