defmodule PhoenixVapor.Runtime do
  @moduledoc """
  Persistent Vue reactive context backed by QuickBEAM.

  Each Runtime holds a QuickBEAM process with Vue's reactivity system loaded.
  `ref()` values become reactive state, `computed()` values auto-update when
  dependencies change, and functions execute in-place against reactive refs.

  State persists across calls — the same reactive graph lives for the lifetime
  of the owning LiveView process.

  ## Usage

      {:ok, rt} = Runtime.start_link(
        refs: %{"count" => "0", "name" => ~s("World")},
        computeds: %{"doubled" => "count * 2"},
        functions: ["increment"],
        function_bodies: %{"increment" => "count++"}
      )

      {:ok, state} = Runtime.get_state(rt)
      {:ok, state} = Runtime.call_handler(rt, "increment", %{})
  """

  use GenServer

  @reactivity_js_path Path.join(:code.priv_dir(:phoenix_vapor), "js/vue-reactivity.js")

  # ── Public API ──

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def get_state(runtime) do
    GenServer.call(runtime, :get_state)
  end

  def call_handler(runtime, function_name, params \\ %{}) do
    GenServer.call(runtime, {:call_handler, function_name, params})
  end

  def set_state(runtime, updates) when is_map(updates) do
    GenServer.call(runtime, {:set_state, updates})
  end

  # ── GenServer callbacks ──

  @impl true
  def init(opts) do
    refs = Keyword.get(opts, :refs, %{})
    computeds = Keyword.get(opts, :computeds, %{})
    functions = Keyword.get(opts, :functions, [])
    function_bodies = Keyword.get(opts, :function_bodies, %{})

    case setup_runtime(refs, computeds, functions, function_bodies) do
      {:ok, qb_rt} ->
        {:ok, %{rt: qb_rt}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    result = QuickBEAM.call(state.rt, "__pv_getState", [])
    {:reply, result, state}
  end

  def handle_call({:call_handler, name, params}, _from, state) do
    result = QuickBEAM.call(state.rt, "__pv_callHandler", [name, params])
    {:reply, result, state}
  end

  def handle_call({:set_state, updates}, _from, state) do
    result = QuickBEAM.call(state.rt, "__pv_setState", [updates])
    {:reply, result, state}
  end

  @impl true
  def terminate(_reason, state) do
    QuickBEAM.stop(state.rt)
    :ok
  end

  # ── Setup ──

  defp setup_runtime(refs, computeds, functions, function_bodies) do
    {:ok, rt} = QuickBEAM.start()

    reactivity_js = File.read!(@reactivity_js_path)
    {:ok, _} = QuickBEAM.eval(rt, reactivity_js)

    setup_code = build_setup_code(refs, computeds, functions, function_bodies)

    case QuickBEAM.eval(rt, setup_code) do
      {:ok, _} -> {:ok, rt}
      {:error, err} ->
        QuickBEAM.stop(rt)
        {:error, err}
    end
  end

  defp build_setup_code(refs, computeds, functions, function_bodies) do
    ref_names = Map.keys(refs)
    computed_names = Map.keys(computeds)

    ref_decls = Enum.map_join(refs, "\n  ", fn {name, init_expr} ->
      "const #{name} = __ref(#{init_expr});"
    end)

    all_reactive_names = ref_names ++ computed_names

    # Sort computeds topologically so dependencies are declared first
    sorted_computeds = topo_sort_computeds(computeds, computed_names)

    # Computed expressions need .value since they access real Vue refs/computeds
    computed_decls = Enum.map_join(sorted_computeds, "\n  ", fn {name, expr} ->
      rewritten = add_value_suffix(expr, all_reactive_names)
      "const #{name} = __computed(() => #{rewritten});"
    end)

    # Scope object with getters/setters for each ref —
    # allows function bodies to use `count++` instead of `count.value++`
    scope_props = Enum.map_join(ref_names, "\n    ", fn name ->
      """
      Object.defineProperty(__scope, #{inspect(name)}, {
          get() { return #{name}.value; },
          set(v) { #{name}.value = v; }
        });\
      """
    end)

    # Function declarations use `with(__scope)` so bare ref names work
    func_decls = Enum.map_join(functions, "\n    ", fn func_name ->
      body = Map.get(function_bodies, func_name, "")
      """
      __handlers[#{inspect(func_name)}] = function(__params) {
          with (__scope) { #{body} }
        };\
      """
    end)

    # getState unwraps reactive proxies via toRaw for clean serialization
    state_entries =
      Enum.map(ref_names, fn n -> "#{inspect(n)}: __unwrap(#{n}.value)" end) ++
        Enum.map(computed_names, fn n -> "#{inspect(n)}: __unwrap(#{n}.value)" end)

    get_state_body = Enum.join(state_entries, ", ")

    set_state_cases = Enum.map_join(ref_names, "\n      ", fn name ->
      "if (u.hasOwnProperty(#{inspect(name)})) #{name}.value = u[#{inspect(name)}];"
    end)

    """
    (function() {
      const { ref: __ref, computed: __computed, toRaw: __toRaw } = VueReactivity;

      function __unwrap(v) {
        const raw = __toRaw(v);
        if (Array.isArray(raw)) return raw.slice();
        if (raw && typeof raw === 'object') return Object.assign({}, raw);
        return raw;
      }

      #{ref_decls}
      #{computed_decls}

      const __scope = {};
      #{scope_props}

      const __handlers = {};
      #{func_decls}

      globalThis.__pv_getState = function() {
        return { #{get_state_body} };
      };

      globalThis.__pv_setState = function(u) {
        #{set_state_cases}
        return globalThis.__pv_getState();
      };

      globalThis.__pv_callHandler = function(name, params) {
        const handler = __handlers[name];
        if (handler) handler(params);
        return globalThis.__pv_getState();
      };
    })();
    """
  end

  defp add_value_suffix(expr, ref_names) do
    Enum.reduce(ref_names, expr, fn name, code ->
      String.replace(code, ~r/\b#{Regex.escape(name)}\b(?!\.value)/, "#{name}.value")
    end)
  end

  defp topo_sort_computeds(computeds, computed_names) do
    deps =
      Map.new(computeds, fn {name, expr} ->
        referenced =
          computed_names
          |> Enum.filter(fn cn -> cn != name && Regex.match?(~r/\b#{Regex.escape(cn)}\b/, expr) end)

        {name, referenced}
      end)

    {sorted, _} =
      Enum.reduce(computed_names, {[], MapSet.new()}, fn _, {acc, visited} ->
        case Enum.find(computed_names, fn n -> n not in visited && Enum.all?(deps[n] || [], &(&1 in visited)) end) do
          nil -> {acc, visited}
          name -> {acc ++ [{name, computeds[name]}], MapSet.put(visited, name)}
        end
      end)

    sorted
  end
end
