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

  @type computed :: {String.t(), Expr.compiled()}

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
          left_out: [{String.t(), [String.t()]}]
        }

  @doc """
  Compiles the computeds, ordered so that each comes after the ones it reads,
  and decides how the server gets each one; see `t:plan/0`.
  """
  @spec compile(ScriptSetup.t()) :: plan()
  def compile(%ScriptSetup{computeds: computeds, props: props, refs: refs}) do
    compiled = Map.new(computeds, fn {name, body} -> {name, compile_body(body)} end)
    server = MapSet.new(Map.keys(refs) ++ props ++ ["props" | Expr.globals()])
    dynamic = MapSet.new(["props" | props])

    # In order, so a computed is decided after the ones it reads.
    {plan, _server, _dynamic} =
      compiled
      |> order()
      |> Enum.reduce({%{constant: [], per_render: [], left_out: []}, server, dynamic}, fn
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

    Map.new(plan, fn {kind, list} -> {kind, Enum.reverse(list)} end)
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
    deps =
      Map.new(compiled, fn {name, expr} ->
        {name, expr |> Expr.assign_keys() |> Enum.filter(&Map.has_key?(compiled, &1))}
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
    Enum.reduce(computeds, {values, assigns}, fn {name, expr}, {values, assigns} ->
      scope = scope(assigns, values)
      value = if opts[:memo], do: memoized(name, expr, scope), else: eval(expr, scope, opts)
      key = Names.atom!(name)
      {Map.put(values, key, value), Map.put(assigns, key, value)}
    end)
  end

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
