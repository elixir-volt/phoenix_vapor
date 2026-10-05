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

  @type computed :: {String.t(), Expr.compiled() | {:elixir, module(), atom()}}

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
  """
  @spec compile(ScriptSetup.t(), %{String.t() => {module(), atom()}}) :: plan()
  def compile(%ScriptSetup{computeds: computeds, props: props, refs: refs}, twins \\ %{}) do
    compiled =
      Map.new(computeds, fn {name, body} ->
        # Declared names get their atoms while compiling; rendering only
        # looks them up.
        Names.atom!(name)

        case twins do
          %{^name => {module, function}} -> {name, {:elixir, module, function}}
          _no_twin -> {name, compile_body(body)}
        end
      end)

    server = MapSet.new(Map.keys(refs) ++ props ++ ["props" | Expr.globals()])
    dynamic = MapSet.new(["props" | props])

    # In order, so a computed is decided after the ones it reads.
    {plan, _server, _dynamic} =
      compiled
      |> order()
      |> Enum.reduce({%{constant: [], per_render: [], left_out: []}, server, dynamic}, fn
        # An Elixir counterpart computes it on every render, from whatever
        # the server has.
        {name, {:elixir, _module, _function} = twin}, {plan, server, dynamic} ->
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

    Enum.reduce(computeds, {values, assigns}, fn {name, expr}, {values, assigns} ->
      value =
        case expr do
          {:elixir, module, function} -> apply(module, function, [assigns])
          expr when memo? -> memoized(name, expr, scope(assigns, values))
          expr -> eval(expr, scope(assigns, values), opts)
        end

      key = Names.existing(name)
      {Map.put(values, key, value), Map.put(assigns, key, value)}
    end)
  end

  @doc """
  The names a computed reads, or `:any` for an Elixir counterpart, which may
  read any assign.
  """
  @spec reads(Expr.compiled() | {:elixir, module(), atom()}) :: [String.t()] | :any
  def reads({:elixir, _module, _function}), do: :any
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
