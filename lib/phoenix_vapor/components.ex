defmodule PhoenixVapor.Components do
  @moduledoc false

  # Compiles a template for the server and resolves the components it uses.
  #
  # A component the SFC imports from a `.vue` file is compiled from that
  # file's template, recursively, and rendered on the server with its props,
  # slots, and fallthrough attributes. A component imported from anywhere
  # else, such as a package, can't be rendered by the server, and is reported
  # as a diagnostic. A component that isn't imported at all is looked up in the
  # `__components__` assign when the template renders.

  alias PhoenixVapor.{Macros, Renderer}

  @type diagnostic :: %{tag: String.t(), file: Path.t() | nil, problem: term()}

  @doc """
  Splits and compiles `template`, resolving the components its SFC imports.

  ## Options

    * `:file` — the SFC's path, for relative imports and diagnostics
    * `:script` — the SFC's `<script setup>` source, for its imports
    * `:events` — passed to `PhoenixVapor.Renderer.compile/2`

  Returns the compiled split, the `.vue` files it read, and diagnostics for
  components the server can't render.
  """
  @spec compile(String.t(), keyword()) :: {map(), [Path.t()], [diagnostic()]}
  def compile(template, opts \\ []) do
    state = %{
      events: Keyword.get(opts, :events, true),
      stack: [],
      cache: %{},
      resources: [],
      diagnostics: [],
      macros: nil
    }

    {split, state} =
      compile_template(template, opts[:file], opts[:script] || "", [], nil, state)

    Macros.stop(state.macros)
    {split, Enum.uniq(state.resources), Enum.reverse(state.diagnostics)}
  end

  @doc """
  Like `compile/2`, but reports diagnostics: `unrendered: :warn` prints them as
  a compile-time warning, for templates the browser renders again, and
  `unrendered: :raise` raises a `CompileError`.

  Also takes `:env`, the caller's `Macro.Env`, for the warning's location.
  Returns the split and the `.vue` files it read.
  """
  @spec compile!(String.t(), keyword()) :: {map(), [Path.t()]}
  def compile!(template, opts) do
    {split, resources, diagnostics} = compile(template, opts)

    case {format(diagnostics), opts[:unrendered]} do
      {nil, _} ->
        :ok

      {message, :warn} ->
        IO.warn(
          "the server's first render leaves out what it can't render; " <>
            "the browser renders it when it mounts the component:\n" <> message,
          opts[:env] || []
        )

      {message, _raise} ->
        raise CompileError, description: message
    end

    {split, resources}
  end

  @doc """
  Formats diagnostics as one message, a line per file and problem, or nil when
  there are none.
  """
  @spec format([diagnostic()]) :: String.t() | nil
  def format([]), do: nil

  def format(diagnostics) do
    diagnostics
    |> Enum.group_by(&{&1.file, &1.problem}, & &1.tag)
    |> Enum.sort()
    |> Enum.map_join("\n", fn {{file, problem}, tags} ->
      tags = tags |> Enum.uniq() |> Enum.map_join(", ", &"<#{&1}>")
      location = if file, do: Path.relative_to_cwd(file) <> ": ", else: ""
      location <> problem_message(problem, tags)
    end)
  end

  defp problem_message({:package, source}, tags),
    do: "#{tags} from #{inspect(source)}, which the server can't render"

  defp problem_message({:not_found, source}, tags), do: "#{tags}: can't find #{inspect(source)}"
  defp problem_message(:recursive, tags), do: "#{tags} renders itself recursively"

  defp problem_message({:dynamic, source}, _tags),
    do: "`#{source}` calls a macro with values known only when rendering"

  defp problem_message({:failed, message}, _tags), do: "a macro call failed: #{message}"

  defp compile_template(template, file, script, split_opts, static_props, state) do
    split =
      template
      |> Vize.vapor_split!(split_opts)
      |> Renderer.compile(events: state.events)

    ctx = %{file: file, imports: imports(script), script: script, static_props: static_props}

    {split, runtime, macro_diagnostics} = Macros.fold(split, ctx, state.macros)

    state =
      Enum.reduce(macro_diagnostics, %{state | macros: runtime}, fn {problem, detail}, state ->
        diagnose(state, nil, file, {problem, detail})
      end)

    resolve_split(split, ctx, state)
  end

  defp resolve_split(%{slots: slots} = split, ctx, state) do
    {slots, state} = Enum.map_reduce(slots, state, &resolve_slot(&1, ctx, &2))
    {%{split | slots: slots}, state}
  end

  defp resolve_slot(%{kind: :if_node, positive: pos, negative: neg} = slot, ctx, state) do
    {pos, state} = resolve_split(pos, ctx, state)
    {neg, state} = resolve_branch(neg, ctx, state)
    {%{slot | positive: pos, negative: neg}, state}
  end

  defp resolve_slot(%{kind: :for_node, render: render} = slot, ctx, state) do
    {render, state} = resolve_split(render, ctx, state)
    {%{slot | render: render}, state}
  end

  defp resolve_slot(%{kind: :slot_outlet, fallback: fallback} = slot, ctx, state) do
    {fallback, state} = resolve_branch(fallback, ctx, state)
    {%{slot | fallback: fallback}, state}
  end

  defp resolve_slot(%{kind: :create_component, slots: slot_fns} = slot, ctx, state) do
    {slot_fns, state} =
      Enum.map_reduce(slot_fns, state, fn slot_fn, state ->
        {render, state} = resolve_split(slot_fn.render, ctx, state)
        {%{slot_fn | render: render}, state}
      end)

    resolve_component(%{slot | slots: slot_fns}, ctx, state)
  end

  defp resolve_slot(slot, _ctx, state), do: {slot, state}

  defp resolve_branch(nil, _ctx, state), do: {nil, state}
  defp resolve_branch(%{kind: _} = slot, ctx, state), do: resolve_slot(slot, ctx, state)
  defp resolve_branch(split, ctx, state), do: resolve_split(split, ctx, state)

  defp resolve_component(%{tag: tag} = slot, ctx, state) do
    case import_for(ctx.imports, tag) do
      nil ->
        {slot, state}

      %{source: source} ->
        if Path.extname(source) == ".vue" do
          resolve_vue(slot, source, ctx, state)
        else
          {slot, diagnose(state, tag, ctx.file, {:package, source})}
        end
    end
  end

  defp resolve_vue(%{tag: tag} = slot, source, ctx, state) do
    case resolve_path(source, ctx.file) do
      {:ok, path} ->
        if path in state.stack do
          {slot, diagnose(state, tag, ctx.file, :recursive)}
        else
          static_props = static_props(slot.props)

          case state.cache[{path, static_props}] do
            nil ->
              {compiled, state} = compile_child(path, static_props, state)
              state = %{state | cache: Map.put(state.cache, {path, static_props}, compiled)}
              {Map.put(slot, :component, compiled), state}

            compiled ->
              {Map.put(slot, :component, compiled), state}
          end
        end

      {:error, _reason} ->
        {slot, diagnose(state, tag, ctx.file, {:not_found, source})}
    end
  end

  # What a component instance knows about its props at compile time: values
  # passed as constants, such as `variant="ghost"` or `:size="'sm'"`, and the
  # names bound to anything else. A prop that isn't passed is `undefined`. A
  # component is compiled once for each combination, so macro calls that use
  # its props can fold.
  defp static_props(props) do
    Enum.reduce(props, %{static: %{}, dynamic: MapSet.new()}, fn prop, acc ->
      case {prop.key, prop.values} do
        {{:static_, key}, [{:static_, value}]} ->
          put_in(acc, [:static, camelize(key)], value)

        {{:static_, key}, [{:expr, _source, %{type: :literal, value: value}, _keys}]} ->
          put_in(acc, [:static, camelize(key)], value)

        {{:static_, key}, _values} ->
          %{acc | dynamic: MapSet.put(acc.dynamic, camelize(key))}

        _dynamic_key ->
          acc
      end
    end)
  end

  defp camelize(key), do: Regex.replace(~r/-(\w)/, key, fn _, char -> String.upcase(char) end)

  defp compile_child(path, static_props, state) do
    source = File.read!(path)
    desc = Vize.parse_sfc!(source)
    script = (desc.script_setup && desc.script_setup.content) || ""
    template = (desc.template && String.trim(desc.template.content)) || ""

    parent_stack = state.stack
    state = %{state | stack: [path | parent_stack], resources: [path | state.resources]}

    # Only a component with macros needs to know its static props.
    static_props =
      if Macros.any?(imports(script)),
        do: Map.put(static_props, :declared, props(source)),
        else: nil

    {split, state} =
      compile_template(template, path, script, [root_attrs: true], static_props, state)

    compiled = %{props: props(source), split: split, events: state.events}
    {compiled, %{state | stack: parent_stack}}
  end

  defp props(source) do
    case Vize.analyze_sfc(source) do
      {:ok, croquis} -> Enum.map(croquis.props, & &1.name)
      {:error, _} -> []
    end
  end

  # Volt resolves the specifier the way the browser build does: relative to
  # the importing file, or through the project's aliases such as `@/`.
  defp resolve_path(source, importer) do
    opts = [importer: importer, aliases: aliases()]

    case Volt.Assets.resolve(source, opts) do
      {:ok, path} -> {:ok, Path.expand(path)}
      error -> error
    end
  end

  defp aliases do
    if Code.ensure_loaded?(Volt.Config), do: Volt.Config.build().aliases, else: %{}
  end

  # A tag matches the import with its name, in either case style: `<my-card>`
  # uses `MyCard`.
  defp import_for(imports, tag) do
    imports[tag] || imports[tag |> String.replace("-", "_") |> Macro.camelize()]
  end

  defp diagnose(state, tag, file, problem) do
    %{state | diagnostics: [%{tag: tag, file: file, problem: problem} | state.diagnostics]}
  end

  @doc false
  # The bindings a `<script setup>` imports: local name to source and
  # import attributes.
  @spec imports(String.t()) :: %{String.t() => map()}
  def imports(script) do
    case OXC.parse(script, "setup.ts") do
      {:ok, ast} ->
        ast
        |> OXC.collect(fn
          %{type: :import_declaration, source: %{value: source}} = decl ->
            {:keep, decl_imports(decl, source)}

          _ ->
            :skip
        end)
        |> List.flatten()
        |> Map.new()

      _ ->
        %{}
    end
  end

  defp decl_imports(decl, source) do
    attributes =
      Map.new(decl[:attributes] || [], fn %{key: key, value: %{value: value}} ->
        {key[:name] || key[:value], value}
      end)

    for specifier <- decl[:specifiers] || [] do
      imported =
        case specifier do
          %{type: :import_default_specifier} -> :default
          %{type: :import_namespace_specifier} -> :namespace
          %{imported: %{name: name}} -> name
          %{imported: %{value: name}} -> name
        end

      {specifier.local.name, %{source: source, imported: imported, attributes: attributes}}
    end
  end
end
