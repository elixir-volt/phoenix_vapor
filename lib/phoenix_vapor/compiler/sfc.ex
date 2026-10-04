defmodule PhoenixVapor.Compiler.SFC do
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

  # The SFC without its `<script lang="elixir">` block, tags included, for
  # compiling it for the browser, using the span the SFC parser reports.
  @spec without_elixir_block(String.t()) :: String.t()
  def without_elixir_block(source) do
    case Vize.parse_sfc(source) do
      {:ok, %{script: %{lang: "elixir", loc: %{tag_start: start, tag_end: stop}}}} ->
        binary_part(source, 0, start) <> binary_part(source, stop, byte_size(source) - stop)

      _ ->
        source
    end
  end

  # The public functions a `<script lang="elixir">` block defines, as their
  # names and the arities they can be called with.
  @spec elixir_functions(map(), Path.t()) :: %{String.t() => MapSet.t(non_neg_integer())}
  def elixir_functions(desc, file) do
    desc
    |> elixir_block(file)
    |> Enum.flat_map(fn
      {:def, _meta, [head | _body]} -> [signature(head)]
      _expr -> []
    end)
    |> Enum.reduce(%{}, fn {name, arities}, acc ->
      Map.update(acc, name, MapSet.new(arities), &MapSet.union(&1, MapSet.new(arities)))
    end)
  end

  defp signature({:when, _meta, [head | _guards]}), do: signature(head)

  defp signature({name, _meta, args}) when is_atom(name) do
    args = List.wrap(args)
    defaults = Enum.count(args, &match?({:\\, _, _}, &1))
    {Atom.to_string(name), (length(args) - defaults)..length(args)//1}
  end

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

  # The `.vue` file a macro names: any expression known at compile time, such
  # as a string or `Path.join(@dir, "Card.vue")`, relative to the caller's
  # directory.
  @spec path!(Macro.t(), Macro.Env.t()) :: Path.t()
  def path!(file, caller) do
    {file, _binding} = Code.eval_quoted(file, [], caller)
    Path.expand(file, Path.dirname(caller.file))
  end
end
