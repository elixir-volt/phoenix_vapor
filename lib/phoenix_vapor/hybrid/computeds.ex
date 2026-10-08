defmodule PhoenixVapor.Hybrid.Computeds do
  @moduledoc false

  # A hybrid component's `computed()` values for the server's first paint.
  #
  # Each body compiles once to a template expression, so it evaluates the way
  # the template's own expressions do: in Elixir, or in QuickBEAM when only
  # JavaScript can. A computed that reads only refs, and computeds like it, is
  # the same on every render: it's evaluated once while compiling, and package
  # components can render with it. One that reads props is evaluated when
  # rendering, and its last value is reused while its inputs are unchanged.

  alias PhoenixVapor.Compiler.ScriptSetup
  alias PhoenixVapor.Renderer.{Expr, Names}

  @typedoc """
  A computed's name, and its compiled body or its Elixir counterpart, with the
  assign keys the counterpart reads.
  """
  @type computed :: {String.t(), Expr.compiled() | {:elixir, module(), atom(), [String.t()]}}

  @typedoc """
  The computeds by how the server gets them: `:constant` read only refs, so
  they're evaluated once while compiling; `:per_render` read props too;
  `:left_out` read something only the browser has, such as a composable's
  result or an import, so the server leaves them, and what reads them, out of
  its render. Each left-out computed comes with the names it lacks.
  """
  @type plan :: %{
          constant: [computed()],
          per_render: [computed()],
          left_out: [{String.t(), [String.t()]}],
          reads: %{String.t() => [String.t()] | :any}
        }

  @doc """
  Compiles the computeds, ordered so that each comes after the ones it reads,
  and decides how the server gets each one; see `t:plan/0`.

    * `:twins` — Elixir counterparts by computed name, `{module, function,
      reads}`
    * `:known` — other names the server has, such as constants
    * `:rewrite` — rewrites a body's AST, such as pointing calls to script
      functions at their Elixir counterparts
  """
  @spec compile(ScriptSetup.t(), keyword()) :: plan()
  def compile(%ScriptSetup{computeds: computeds, refs: refs} = setup, opts \\ []) do
    twins = Keyword.get(opts, :twins, %{})
    rewrite = Keyword.get(opts, :rewrite, & &1)

    compiled =
      Map.new(computeds, fn {name, body} ->
        # Evaluating while compiling looks names up; the render spec
        # carries their atoms for rendering.
        Names.atom!(name)

        case twins do
          %{^name => {module, function, reads}} -> {name, {:elixir, module, function, reads}}
          _no_twin -> {name, body |> compile_body() |> rewrite_calls(rewrite)}
        end
      end)

    known = Keyword.get(opts, :known, [])
    # A model is a prop the browser may change: the server has it on every
    # render, as an assign.
    props = setup.props ++ Map.keys(setup.models)
    server = MapSet.new(Map.keys(refs) ++ props ++ known ++ ["props" | Expr.globals()])
    dynamic = MapSet.new(["props" | props])

    # In order, so a computed is decided after the ones it reads.
    {plan, _server, _dynamic} =
      compiled
      |> order()
      |> Enum.reduce({%{constant: [], per_render: [], left_out: []}, server, dynamic}, fn
        # An Elixir counterpart computes it on every render, from whatever
        # the server has.
        {name, {:elixir, _module, _function, _reads} = twin}, {plan, server, dynamic} ->
          plan = %{plan | per_render: [{name, twin} | plan.per_render]}
          {plan, MapSet.put(server, name), MapSet.put(dynamic, name)}

        {name, expr}, {plan, server, dynamic} ->
          keys = Expr.assign_keys(expr)

          cond do
            (missing = Enum.reject(keys, &MapSet.member?(server, &1))) != [] ->
              {%{plan | left_out: [{name, missing} | plan.left_out]}, server, dynamic}

            Enum.any?(keys, &MapSet.member?(dynamic, &1)) ->
              plan = %{plan | per_render: [{name, expr} | plan.per_render]}
              {plan, MapSet.put(server, name), MapSet.put(dynamic, name)}

            true ->
              {%{plan | constant: [{name, expr} | plan.constant]}, MapSet.put(server, name),
               dynamic}
          end
      end)

    plan
    |> Map.new(fn {kind, list} -> {kind, Enum.reverse(list)} end)
    |> Map.put(:reads, Map.new(compiled, fn {name, expr} -> {name, reads(expr)} end))
  end

  # Calls to script functions with Elixir counterparts run those instead.
  defp rewrite_calls({tag, source, node, _keys}, rewrite)
       when tag in [:expr, :js] and is_map(node),
       do: Expr.from_node(source, rewrite.(node))

  defp rewrite_calls(expr, _rewrite), do: expr

  # A block body runs as a function's.
  defp compile_body(body) do
    if String.starts_with?(String.trim_leading(body), "{"),
      do: Expr.compile("(() => " <> body <> ")()"),
      else: Expr.compile(body)
  end

  # Each computed after the computeds it reads; a cycle stops at the first
  # computed seen again.
  defp order(compiled) do
    # An Elixir counterpart may read any computed, so it comes after the
    # JavaScript ones.
    javascript = for {name, expr} <- compiled, reads(expr) != :any, do: name

    deps =
      Map.new(compiled, fn {name, expr} ->
        case reads(expr) do
          :any -> {name, javascript}
          keys -> {name, Enum.filter(keys, &Map.has_key?(compiled, &1))}
        end
      end)

    compiled
    |> Map.keys()
    |> Enum.sort()
    |> Enum.reduce([], &visit(&1, &2, deps, []))
    |> Enum.reverse()
    |> Enum.map(&{&1, Map.fetch!(compiled, &1)})
  end

  # `done` is in reverse order.
  defp visit(name, done, deps, visiting) do
    if name in done or name in visiting do
      done
    else
      done = Enum.reduce(deps[name], done, &visit(&1, &2, deps, [name | visiting]))
      [name | done]
    end
  end

  @doc """
  Evaluates computeds in order against `values`, the refs' and earlier
  computeds' values by atom, and `assigns`, adding each value to both.
  `<script setup>` reads a ref or computed as `.value`.

    * `:runtime` — evaluates JavaScript-only bodies there
    * `:memo` — reuses the process's last value of a computed whose inputs
      are unchanged
  """
  @spec evaluate([computed()], map(), map(), keyword()) :: {map(), map()}
  def evaluate(computeds, values, assigns, opts \\ []) do
    memo? = Keyword.get(opts, :memo, false)

    Enum.reduce(computeds, {values, assigns}, fn
      # A counterpart reading state the render doesn't have, such as a
      # composable's value before the browser reports it, isn't called: its
      # computed is absent too.
      {name, {:elixir, module, function, reads}}, {values, assigns} ->
        if Enum.any?(reads, &absent?(assigns, &1)),
          do: {values, Map.update!(assigns, :__absent__, &MapSet.put(&1, name))},
          else: put(values, assigns, name, apply(module, function, [assigns]))

      {name, expr}, {values, assigns} when memo? ->
        put(values, assigns, name, memoized(name, expr, scope(assigns, values)))

      {name, expr}, {values, assigns} ->
        put(values, assigns, name, eval(expr, scope(assigns, values), opts))
    end)
  end

  defp absent?(%{__absent__: absent}, name), do: MapSet.member?(absent, name)
  defp absent?(_assigns, _name), do: false

  defp put(values, assigns, name, value) do
    key = Names.existing(name)
    {Map.put(values, key, value), Map.put(assigns, key, value)}
  end

  @doc """
  The names a computed reads, or `:any` for an Elixir counterpart, which may
  read any assign.
  """
  @spec reads(Expr.compiled() | {:elixir, module(), atom(), [String.t()]}) ::
          [String.t()] | :any
  def reads({:elixir, _module, _function, _reads}), do: :any
  def reads(expr), do: Expr.assign_keys(expr)

  defp eval(expr, scope, opts), do: Expr.eval(expr, scope, Keyword.take(opts, [:runtime]))

  defp memoized(name, expr, scope) do
    inputs = Enum.map(Expr.assign_keys(expr), &lookup(scope, &1))

    case Process.get({__MODULE__, name, expr}) do
      {^inputs, value} ->
        value

      _other ->
        value = eval(expr, scope, [])
        Process.put({__MODULE__, name, expr}, {inputs, value})
        value
    end
  end

  # The assigns with each ref and computed as `{ value }`, by atom and by name.
  defp scope(assigns, values) do
    Enum.reduce(values, assigns, fn {key, value}, scope ->
      wrapped = %{"value" => Map.get(assigns, key, value)}
      scope |> Map.put(key, wrapped) |> Map.put(Atom.to_string(key), wrapped)
    end)
  end

  defp lookup(scope, name), do: Map.get(scope, Names.existing(name), Map.get(scope, name))
end
