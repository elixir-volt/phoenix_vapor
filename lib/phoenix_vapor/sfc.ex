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

  # A `<template>` block's content without surrounding whitespace, and the
  # `{line, column}` in the file where that content starts.
  @spec template(map()) :: {String.t(), {pos_integer(), pos_integer()}} | nil
  def template(%{template: %{content: content, loc: loc}}) do
    trimmed = String.trim_leading(content)
    leading = binary_part(content, 0, byte_size(content) - byte_size(trimmed))

    origin =
      case String.split(leading, "\n") do
        [same_line] -> {loc.start_line, loc.start_column + String.length(same_line)}
        lines -> {loc.start_line + length(lines) - 1, String.length(List.last(lines)) + 1}
      end

    {String.trim_trailing(trimmed), origin}
  end

  def template(_desc), do: nil

  # Like `template/1`, but raises when the SFC has no `<template>` block.
  @spec template!(map(), Path.t()) :: {String.t(), {pos_integer(), pos_integer()}}
  def template!(desc, file) do
    template(desc) ||
      raise CompileError,
        file: file,
        line: 1,
        description: "no <template> block in #{Path.relative_to_cwd(file)}"
  end
end
