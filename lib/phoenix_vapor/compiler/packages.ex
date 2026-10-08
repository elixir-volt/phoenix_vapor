defmodule PhoenixVapor.Compiler.Packages do
  @moduledoc false

  # Renders components from packages, such as Reka UI, at compile time.
  #
  # The server can't render a package component itself: its markup comes from
  # its JavaScript. When everything the component receives is known at compile
  # time, Vue's server renderer runs it once in QuickBEAM, with the template's
  # own content inside it left as holes, and its HTML becomes part of the
  # template. A whole subtree renders together, so parts that need their
  # parent's context, such as Reka's `TabsList` inside `TabsRoot`, work.
  #
  # Known values are literals, folded macro calls, and in hybrid mode the
  # initial values of client refs, which is what the browser first renders
  # too. A component that receives a value known only when rendering, or a
  # scoped slot, can't be folded.

  alias PhoenixVapor.Template
  alias PhoenixVapor.Renderer.Expr

  @marker_pattern ~r/\x{2063}H(\d+)\x{2063}/u
  @capture_pattern ~r/\x{2063}C(\d+)\.(\d+)\[\x{2063}(.*?)\x{2063}C\1\.\2\]\x{2063}/su

  @type package :: %{source: String.t(), imported: :default | :namespace | String.t()}

  @doc """
  Folds a component slot whose component comes from a package.

  `packages` returns a tag's package import, or nil for a tag that isn't a
  package component, for the component and the ones inside it. `known` holds
  the values names have at compile time. Returns a `:fragment` slot, whose
  holes still need resolving, or the reason it can't fold.

  In `:all` mode, for hybrid templates, whose browser takes over, a component
  folds into whatever markup it renders. In `:content` mode, for templates
  nothing takes over in the browser, it folds only when it renders just its
  content, as a provider does: frozen markup from a component with behavior,
  such as tabs, would look interactive and do nothing.
  """
  @spec fold(map(), (String.t() -> package() | nil), map(), pid(), Path.t(), :all | :content) ::
          {:ok, map()} | {:error, String.t()}
  def fold(slot, packages, known, runtime, file, mode \\ :all) do
    # Each component is checked on its own when only content may render.
    packages = if mode == :content, do: &if(&1 == slot.name, do: packages.(&1)), else: packages

    with {:ok, tree, holes} <- tree(slot, packages, known, []),
         {:ok, html} <- render(runtime, tree),
         :ok <- check_content(mode, html, tree),
         {:ok, template} <- template(html, Enum.reverse(holes), file) do
      {:ok,
       %{
         kind: :fragment,
         template: template,
         reads: reads(slot, packages),
         position: slot.position
       }}
    end
  end

  # The prop expressions of the folded components, which decide their markup
  # though rendering no longer evaluates them, so change tracking and session
  # replays still count them: the component's own, and those of package
  # components rendered with it, inside its content or our `v-for` and `v-if`
  # around them. Its other content stays in the template.
  defp reads(%{kind: :component} = slot, packages) do
    if packages.(slot.name) do
      props = for %{value: value} <- slot.props, folded_expr?(value), do: value
      props ++ Enum.flat_map(Template.blocks(slot), &block_reads(&1, packages))
    else
      []
    end
  end

  defp reads(%{kind: kind} = slot, packages) when kind in [:for, :if],
    do: Enum.flat_map(Template.blocks(slot), &block_reads(&1, packages))

  defp reads(_slot, _packages), do: []

  defp block_reads(%{slots: slots}, packages), do: Enum.flat_map(slots, &reads(&1, packages))

  defp folded_expr?({tag, _source, _node, _keys}) when tag in [:expr, :js, :lookup], do: true
  defp folded_expr?(_value), do: false

  defp check_content(:all, _html, _tree), do: :ok

  defp check_content(:content, html, tree) do
    content = tree.slots |> Map.get("default", []) |> Enum.join()

    if map_size(Map.delete(tree.slots, "default")) == 0 and strip_fragments(html) == content,
      do: :ok,
      else:
        {:error,
         "it has markup and behavior of its own, which work only in hybrid mode, where Vue runs in the browser"}
  end

  # The component as a tree for Vue: its props, and each slot's content as
  # HTML with markers for the template's own content, or nested package
  # components.
  defp tree(%{kind: :component, name: name} = slot, packages, known, holes) do
    package = packages.(name)

    with :ok <- check_slots(slot),
         {:ok, props} <- props(slot.props, known) do
      Enum.reduce_while(slot.slots, {:ok, %{}, holes}, fn content, {:ok, slots, holes} ->
        case parts(content.block, packages, known, holes) do
          {:ok, parts, holes} -> {:cont, {:ok, Map.put(slots, content.name, parts), holes}}
          error -> {:halt, error}
        end
      end)
      |> case do
        {:ok, slots, holes} ->
          {:ok,
           %{source: package.source, name: imported(package, name), props: props, slots: slots},
           holes}

        error ->
          error
      end
    end
  end

  defp check_slots(%{name: name, slots: slots}) do
    cond do
      Enum.any?(slots, &(&1.params != nil)) ->
        {:error, "<#{name}> passes props to its slot content"}

      Enum.any?(slots, &(&1.name == nil)) ->
        {:error, "<#{name}> has a slot with a dynamic name"}

      true ->
        :ok
    end
  end

  defp imported(%{imported: :default}, _name), do: "default"
  defp imported(%{imported: :namespace}, name), do: name
  defp imported(%{imported: imported}, _name), do: imported

  defp parts(%Template{statics: statics, slots: slots}, packages, known, holes) do
    statics
    |> Enum.zip(slots ++ [nil])
    |> Enum.reduce_while({:ok, [], holes}, fn {static, slot}, {:ok, parts, holes} ->
      parts = [static | parts]

      cond do
        slot == nil ->
          {:cont, {:ok, parts, holes}}

        # A nested package component that can't render becomes a hole, so the
        # rest still renders and it's resolved, and reported, on its own.
        slot.kind == :component and packages.(slot.name) != nil ->
          case tree(slot, packages, known, holes) do
            {:ok, node, holes} -> {:cont, {:ok, [node | parts], holes}}
            {:error, _reason} -> {:cont, {:ok, [marker(holes) | parts], [slot | holes]}}
          end

        # Our own `v-for` or `v-if` around package components, such as a
        # tooltip per row, renders each block once here, in its ancestors'
        # context, and stays a hole whose blocks are the rendered templates.
        slot.kind in [:for, :if] and Enum.any?(Template.blocks(slot), &packages?(&1, packages)) ->
          case captures(slot, packages, known, holes, parts) do
            {:ok, parts, holes} -> {:cont, {:ok, parts, holes}}
            error -> {:halt, error}
          end

        true ->
          {:cont, {:ok, [marker(holes) | parts], [slot | holes]}}
      end
    end)
    |> case do
      {:ok, parts, holes} -> {:ok, merge_html(Enum.reverse(parts)), holes}
      error -> error
    end
  end

  defp packages?(%{slots: slots}, packages) do
    Enum.any?(slots, fn slot ->
      (slot.kind == :component and packages.(slot.name) != nil) or
        Enum.any?(Template.blocks(slot), &packages?(&1, packages))
    end)
  end

  # Adds the parts for each of a slot's blocks between capture markers to
  # `parts/4`'s accumulator, which is in reverse. The slot is the hole the
  # captured blocks are put back into.
  defp captures(slot, packages, known, holes, parts) do
    index = length(holes)

    slot
    |> Template.blocks()
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, parts, [slot | holes]}, fn {block, branch}, {:ok, acc, holes} ->
      case parts(block, packages, known, holes) do
        {:ok, inner, holes} ->
          id = "#{index}.#{branch}"

          {:cont,
           {:ok, ["\u2063C#{id}]\u2063" | Enum.reverse(inner, ["\u2063C#{id}[\u2063" | acc])],
            holes}}

        error ->
          {:halt, error}
      end
    end)
  end

  defp strip_fragments(html), do: String.replace(html, ["<!--[-->", "<!--]-->"], "")

  defp marker(holes), do: "\u2063H#{length(holes)}\u2063"

  defp merge_html(parts) do
    parts
    |> Enum.chunk_by(&is_binary/1)
    |> Enum.flat_map(fn
      [html | _] = chunk when is_binary(html) -> [IO.iodata_to_binary(chunk)]
      nodes -> nodes
    end)
    |> Enum.reject(&(&1 == ""))
  end

  # A prop is known when it's static, a folded macro call, or an expression of
  # names in `known`.
  defp props(props, known) do
    Enum.reduce_while(props, {:ok, %{}}, fn prop, {:ok, acc} ->
      case prop_value(prop, known) do
        {:ok, value} ->
          {:cont, {:ok, Map.put(acc, prop.name, value)}}

        :unknown ->
          {:halt, {:error, "the prop `#{prop_label(prop)}` is only known when rendering"}}
      end
    end)
  end

  defp prop_value(%{name: name, name_value: nil, value: nil, static: static}, _known)
       when name != nil,
       do: {:ok, static}

  defp prop_value(%{name: name, name_value: nil, value: value}, known) when name != nil,
    do: known_value(value, known)

  defp prop_value(_spread_or_dynamic_name, _known), do: :unknown

  defp known_value({:value, value}, _known), do: {:ok, value}

  defp known_value(
         {:expr, _source,
          %{type: :member_expression, object: %{name: "props"}, property: %{name: name}}, _keys},
         known
       ) do
    case Map.fetch(known, name) do
      {:ok, value} -> {:ok, value}
      :error -> :unknown
    end
  end

  # An expression of known names, such as `target !== null` over a ref's
  # initial value, evaluates as the template's expressions do when rendering.
  defp known_value({:expr, _source, node, keys} = expr, known) when is_map(node) do
    if Enum.all?(keys, &Map.has_key?(known, &1)) do
      {:ok, Expr.eval(expr, known)}
    else
      :unknown
    end
  rescue
    _error in PhoenixVapor.ExpressionError -> :unknown
  end

  defp known_value(_expr, _known), do: :unknown

  defp prop_label(%{name: name}) when name != nil, do: name
  defp prop_label(_prop), do: "v-bind"

  defp render(runtime, tree) do
    case QuickBEAM.call(runtime, "__pv_fold_render", [tree]) do
      {:ok, html} when is_binary(html) -> {:ok, html}
      {:ok, other} -> {:error, "rendering returned #{inspect(other)}"}
      {:error, error} -> {:error, PhoenixVapor.JS.error_message(error)}
    end
  end

  # Vue's fragment markers are for hydration; the browser mounts fresh.
  defp template(html, holes, file),
    do: html |> strip_fragments() |> split(List.to_tuple(holes), file)

  defp split(html, holes, file) do
    with {:ok, html, captured} <- extract_captures(html, holes, file) do
      [first | rest] = Regex.split(@marker_pattern, html, include_captures: true)

      {statics, indices} =
        rest
        |> Enum.chunk_every(2)
        |> Enum.reduce({[first], []}, fn [marker, static], {statics, indices} ->
          [_, index] = Regex.run(@marker_pattern, marker)
          {[static | statics], [String.to_integer(index) | indices]}
        end)

      indices = Enum.reverse(indices)

      if Enum.uniq(indices) == indices do
        slots = Enum.map(indices, &restore(elem(holes, &1), captured[&1]))
        {:ok, Template.new(Enum.reverse(statics), slots, file)}
      else
        {:error, "its content renders more than once"}
      end
    end
  end

  # The blocks rendered between capture markers, as templates by hole and
  # branch, with the HTML left holding the hole's marker in their place.
  defp extract_captures(html, holes, file) do
    @capture_pattern
    |> Regex.scan(html, capture: :all_but_first)
    |> Enum.reduce_while({:ok, %{}}, fn [index, branch, body], {:ok, captured} ->
      case split(body, holes, file) do
        {:ok, template} ->
          key = {String.to_integer(index), String.to_integer(branch)}
          {:cont, {:ok, Map.put(captured, key, template)}}

        error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, captured} ->
        html =
          Regex.replace(@capture_pattern, html, fn _match, index, branch, _body ->
            if branch == "0", do: "\u2063H#{index}\u2063", else: ""
          end)

        by_hole =
          Enum.group_by(captured, fn {{index, _}, _} -> index end, fn {{_, branch}, t} ->
            {branch, t}
          end)

        {:ok, html, Map.new(by_hole, fn {index, blocks} -> {index, Map.new(blocks)} end)}

      error ->
        error
    end
  end

  defp restore(slot, nil), do: slot
  defp restore(%{kind: :for} = slot, %{0 => block}), do: %{slot | block: block}

  defp restore(%{kind: :if, branches: branches} = slot, blocks) do
    branches =
      branches
      |> Enum.with_index()
      |> Enum.map(fn {branch, index} -> %{branch | block: Map.fetch!(blocks, index)} end)

    %{slot | branches: branches}
  end

  @doc """
  Loads Vue's server renderer and the given packages into `runtime`: the
  `compile/packages.ts` template in `priv/ts`, with the packages imported, bundled
  with Volt from the SFC's directory.
  """
  @spec load(pid(), [String.t()], Path.t()) :: :ok | {:error, String.t()}
  def load(runtime, sources, file) do
    {imports, modules} = PhoenixVapor.JS.module_splices(sources)

    entry =
      Volt.Priv.render!({:phoenix_vapor, "ts"}, "compile/packages.ts", [],
        splices: [imports: imports, modules: modules]
      )

    with {:ok, code} <- bundle(entry, file),
         {:ok, _} <- QuickBEAM.eval(runtime, code) do
      :ok
    else
      {:error, reason} -> {:error, PhoenixVapor.JS.error_message(reason)}
    end
  end

  defp bundle(entry, file) do
    PhoenixVapor.JS.bundle(entry, file,
      name: "fold",
      minify: true,
      define: %{
        "process.env.NODE_ENV" => ~s("production"),
        "__VUE_OPTIONS_API__" => "true",
        "__VUE_PROD_DEVTOOLS__" => "false",
        "__VUE_PROD_HYDRATION_MISMATCH_DETAILS__" => "false"
      }
    )
  end
end
