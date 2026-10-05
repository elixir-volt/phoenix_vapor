defmodule PhoenixVapor.Compiler.SFC do
  @moduledoc false

  # A `.vue` file, read and parsed once: its `<template>` and where it starts,
  # what its `<script setup>` declares, and its `<script lang="elixir">`
  # block, which is compiled into the LiveView module and never reaches Vue.

  alias PhoenixVapor.Compiler.ScriptSetup

  # A template string compiles as an SFC without a descriptor.
  defstruct [
    :file,
    :source,
    :descriptor,
    :template,
    origin: {1, 1},
    setup: %ScriptSetup{},
    elixir: []
  ]

  @type t :: %__MODULE__{
          file: Path.t() | nil,
          source: String.t(),
          descriptor: map() | nil,
          template: String.t() | nil,
          origin: {pos_integer(), pos_integer()},
          setup: ScriptSetup.t(),
          elixir: [Macro.t()]
        }

  @doc """
  The `.vue` file a macro names: any expression known at compile time, such
  as a string or `Path.join(@dir, "Card.vue")`, relative to the caller's
  directory.
  """
  @spec load!(Macro.t(), Macro.Env.t()) :: t()
  def load!(file, caller), do: file |> path!(caller) |> read!()

  @doc "Reads and parses the `.vue` file at `path`."
  @spec read!(Path.t()) :: t()
  def read!(path) do
    source = File.read!(path)
    descriptor = Vize.parse_sfc!(source)
    {template, origin} = template(descriptor) || {nil, {1, 1}}

    %__MODULE__{
      file: path,
      source: source,
      descriptor: descriptor,
      template: template,
      origin: origin,
      setup: ScriptSetup.parse(descriptor.script_setup && descriptor.script_setup.content),
      elixir: elixir_block(descriptor, path)
    }
  end

  @spec path!(Macro.t(), Macro.Env.t()) :: Path.t()
  defp path!(file, caller) do
    {file, _binding} = Code.eval_quoted(file, [], caller)
    Path.expand(file, Path.dirname(caller.file))
  end

  @doc """
  The line in the file where `<script setup>` declares `name`, or 1 when it
  doesn't.
  """
  @spec setup_line(t(), String.t()) :: pos_integer()
  def setup_line(%__MODULE__{setup: setup, descriptor: %{script_setup: %{loc: loc}}}, name) do
    case setup.offsets do
      %{^name => offset} ->
        loc.start_line +
          (setup.source |> binary_part(0, offset) |> String.split("\n") |> length()) - 1

      _other ->
        1
    end
  end

  def setup_line(_sfc, _name), do: 1

  @doc """
  The line in the file where `<script lang="elixir">` first defines
  `function`, or 1 when it doesn't.
  """
  @spec elixir_line(t(), String.t()) :: pos_integer()
  def elixir_line(%__MODULE__{elixir: elixir, descriptor: %{script: %{loc: loc}}}, function) do
    name = String.to_existing_atom(function)

    case Enum.find(elixir, &defines?(&1, name)) do
      {:def, meta, _args} -> loc.start_line + Keyword.get(meta, :line, 1) - 1
      nil -> 1
    end
  end

  def elixir_line(_sfc, _function), do: 1

  @doc "The template, raising when the file has no `<template>` block."
  @spec template!(t()) :: String.t()
  def template!(%__MODULE__{template: nil, file: file}) do
    raise CompileError,
      file: file,
      line: 1,
      description: "no <template> block in #{Path.relative_to_cwd(file)}"
  end

  def template!(%__MODULE__{template: template}), do: template

  @doc """
  Whether `<script setup>` declares state the browser owns: a `ref()`, or a
  name bound by a call the compiler can't run, such as a composable's.
  """
  @spec client_state?(t()) :: boolean()
  def client_state?(%__MODULE__{setup: setup}),
    do: map_size(setup.refs) > 0 or setup.client_bindings != []

  @doc """
  What a template call to a `<script setup>` function can render through on
  the server: each `def` in `<script lang="elixir">`, by name, with the
  arities it accepts.
  """
  @spec elixir_functions(t()) :: %{String.t() => MapSet.t(non_neg_integer())}
  def elixir_functions(%__MODULE__{elixir: elixir}) do
    elixir
    |> Enum.flat_map(fn
      {:def, _meta, [head | _body]} -> [signature(head)]
      _expr -> []
    end)
    |> Enum.reduce(%{}, fn {name, arities}, acc ->
      Map.update(acc, name, MapSet.new(arities), &MapSet.union(&1, MapSet.new(arities)))
    end)
  end

  @doc """
  The assign keys a `<script lang="elixir">` function reads from its
  argument: an over-approximation, for deciding what to record.

  A key in a map pattern (`%{contacts: contacts}`) or read as `assigns.key`
  is required: the function fails without it. One read as `assigns[:key]`
  is optional, nil when missing. With `required: true`, only the required
  keys.
  """
  @spec elixir_reads(t(), String.t(), keyword()) :: [String.t()]
  def elixir_reads(%__MODULE__{elixir: elixir}, function, opts \\ []) do
    name = String.to_existing_atom(function)
    optional? = not Keyword.get(opts, :required, false)

    elixir
    |> Enum.filter(&defines?(&1, name))
    |> Macro.prewalk([], fn
      {:%{}, _meta, pairs} = node, acc when is_list(pairs) ->
        {node, for({key, _value} when is_atom(key) <- pairs, do: Atom.to_string(key)) ++ acc}

      {{:., _, [{_var, _, context}, key]}, _meta, []} = node, acc
      when is_atom(key) and is_atom(context) ->
        {node, [Atom.to_string(key) | acc]}

      {{:., _, [Access, :get]}, _meta, [_assigns, key]} = node, acc
      when optional? and is_atom(key) ->
        {node, [Atom.to_string(key) | acc]}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
    |> Enum.uniq()
  end

  defp defines?({:def, _meta, [{:when, _, [head | _guards]} | _body]}, name),
    do: defines?({:def, [], [head]}, name)

  defp defines?({:def, _meta, [{name, _, _args} | _body]}, name), do: true
  defp defines?(_expr, _name), do: false

  defp signature({:when, _meta, [head | _guards]}), do: signature(head)

  defp signature({name, _meta, args}) when is_atom(name) do
    args = List.wrap(args)
    defaults = Enum.count(args, &match?({:\\, _, _}, &1))
    {Atom.to_string(name), (length(args) - defaults)..length(args)//1}
  end

  @doc """
  The source without its `<script lang="elixir">` block, tags included, for
  compiling it for the browser, using the span the SFC parser reports.
  """
  @spec without_elixir_block(t() | String.t()) :: String.t()
  def without_elixir_block(%__MODULE__{source: source, descriptor: descriptor}),
    do: strip(source, descriptor)

  def without_elixir_block(source) when is_binary(source) do
    case Vize.parse_sfc(source) do
      {:ok, descriptor} -> strip(source, descriptor)
      {:error, _error} -> source
    end
  end

  defp strip(source, %{script: %{lang: "elixir", loc: %{tag_start: start, tag_end: stop}}}),
    do: binary_part(source, 0, start) <> binary_part(source, stop, byte_size(source) - stop)

  defp strip(source, _descriptor), do: source

  # The expressions of a `<script lang="elixir">` block.
  defp elixir_block(%{script: %{lang: "elixir", content: content}}, file)
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

  defp elixir_block(_descriptor, _file), do: []

  # A `<template>` block's content without surrounding whitespace, and the
  # `{line, column}` in the file where that content starts.
  defp template(%{template: %{content: content, loc: loc}}) do
    trimmed = String.trim_leading(content)
    leading = binary_part(content, 0, byte_size(content) - byte_size(trimmed))

    origin =
      case String.split(leading, "\n") do
        [same_line] -> {loc.start_line, loc.start_column + String.length(same_line)}
        lines -> {loc.start_line + length(lines) - 1, String.length(List.last(lines)) + 1}
      end

    {String.trim_trailing(trimmed), origin}
  end

  defp template(_descriptor), do: nil
end
