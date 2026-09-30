defmodule PhoenixVapor.SFC do
  @moduledoc false

  # The expressions of a `<script lang="elixir">` block, to inject into the
  # LiveView module compiled from the SFC.
  @spec elixir_block(map(), Path.t()) :: [Macro.t()]
  def elixir_block(%{script: %{lang: "elixir", content: content}}, file)
      when is_binary(content) do
    case Code.string_to_quoted(content, file: file) do
      {:ok, {:__block__, _, exprs}} ->
        exprs

      {:ok, expr} ->
        [expr]

      {:error, {meta, msg, token}} ->
        line = Keyword.get(List.wrap(meta), :line, 0)
        raise CompileError, file: file, line: line, description: "#{msg}#{token}"
    end
  end

  def elixir_block(_desc, _file), do: []
end
