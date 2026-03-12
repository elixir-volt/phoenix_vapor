defmodule PhoenixVapor.JsEval do
  @moduledoc """
  Evaluates JavaScript expressions via QuickBEAM when the pure-Elixir
  AST evaluator can't handle them (arrow functions, method chains, etc.).

  Requires `quickbeam` as an optional dependency. When not available,
  complex expressions return `nil`.
  """

  @doc """
  Evaluate a JS expression string with assigns injected as variables.
  Returns the result or nil on failure.
  """
  def eval(expr, assigns) when is_binary(expr) do
    if quickbeam_available?() do
      do_eval(expr, assigns)
    end
  end

  defp do_eval(expr, assigns) do
    rt = get_runtime()

    setup =
      assigns
      |> Enum.filter(fn {k, _} -> is_atom(k) and k != :__changed__ and k != :__components__ end)
      |> Enum.map(fn {k, v} -> "var #{k} = #{Jason.encode!(v)};" end)
      |> Enum.join("\n")

    code = "#{setup}\n(#{expr})"

    case QuickBEAM.eval(rt, code) do
      {:ok, result} -> result
      _ -> nil
    end
  end

  defp quickbeam_available? do
    Code.ensure_loaded?(QuickBEAM)
  end

  defp get_runtime do
    case Process.get(:phoenix_vapor_quickbeam_rt) do
      nil ->
        {:ok, rt} = QuickBEAM.start()
        Process.put(:phoenix_vapor_quickbeam_rt, rt)
        rt

      rt ->
        rt
    end
  end
end
