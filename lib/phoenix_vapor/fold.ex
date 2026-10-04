defmodule PhoenixVapor.Fold do
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

  alias PhoenixVapor.LiveVue.EntryPlugin
  alias PhoenixVapor.{Renderer, Template}

  @marker_pattern ~r/\x{2063}H(\d+)\x{2063}/u

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
      {:ok, %{kind: :fragment, template: template, position: slot.position}}
    end
  end

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

        true ->
          {:cont, {:ok, [marker(holes) | parts], [slot | holes]}}
      end
    end)
    |> case do
      {:ok, parts, holes} -> {:ok, merge_html(Enum.reverse(parts)), holes}
      error -> error
    end
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

  # A prop is known when it's static, a folded macro call, a literal, or a name
  # in `known`.
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

  defp known_value({:expr, _source, %{type: :literal, value: value}, _keys}, _known),
    do: {:ok, value}

  defp known_value({:expr, _source, %{type: :identifier, name: name}, _keys}, known) do
    case Map.fetch(known, name) do
      {:ok, value} -> {:ok, value}
      :error -> :unknown
    end
  end

  defp known_value(
         {:expr, source,
          %{type: :member_expression, object: %{name: "props"}, property: %{name: name}}, keys},
         known
       ),
       do: known_value({:expr, source, %{type: :identifier, name: name}, keys}, known)

  defp known_value(_expr, _known), do: :unknown

  defp prop_label(%{name: name}) when name != nil, do: name
  defp prop_label(_prop), do: "v-bind"

  defp render(runtime, tree) do
    case QuickBEAM.eval(runtime, "globalThis.__pv_fold.render(#{Jason.encode!(tree)})") do
      {:ok, html} when is_binary(html) -> {:ok, html}
      {:ok, other} -> {:error, "rendering returned #{inspect(other)}"}
      {:error, error} -> {:error, Exception.message(error)}
    end
  end

  # Vue's fragment markers are for hydration; the browser mounts fresh.
  defp template(html, holes, file) do
    html = strip_fragments(html)
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
      holes = List.to_tuple(holes)
      slots = Enum.map(indices, &elem(holes, &1))
      {:ok, Renderer.template(Enum.reverse(statics), slots, file)}
    else
      {:error, "its content renders more than once"}
    end
  end

  @doc """
  Loads Vue's server renderer and the given packages into `runtime`, bundled
  with Volt from the SFC's directory.
  """
  @spec load(pid(), [String.t()], Path.t()) :: :ok | {:error, String.t()}
  def load(runtime, sources, file) do
    sources = Enum.with_index(sources)

    imports =
      Enum.map_join(sources, "\n", fn {source, i} ->
        "import * as m#{i} from #{Jason.encode!(source)};"
      end)

    modules =
      Enum.map_join(sources, ", ", fn {source, i} -> "#{Jason.encode!(source)}: m#{i}" end)

    entry = """
    import { createSSRApp, h, createStaticVNode } from "vue";
    import { renderToString } from "vue/server-renderer";
    #{imports}
    const modules = {#{modules}};

    function build(node) {
      const component = modules[node.source][node.name];
      const slots = {};
      for (const [name, parts] of Object.entries(node.slots)) {
        slots[name] = () => parts.map((part) => typeof part === "string" ? createStaticVNode(part, 0) : build(part));
      }
      return h(component, node.props, slots);
    }

    // An error or warning while rendering means the output can't be trusted,
    // such as a part rendered without the parent whose context it needs. Vue
    // catches what its handlers throw, so they collect the problems instead.
    function render(tree) {
      const problems = [];
      const app = createSSRApp({ render: () => build(tree) });
      app.config.errorHandler = (error) => { problems.push(error && error.message ? error.message : String(error)); };
      app.config.warnHandler = (message) => { problems.push(message); };
      return renderToString(app).then((html) => {
        if (problems.length > 0) throw new Error(problems[0]);
        return html;
      });
    }

    globalThis.__pv_fold = { render };
    """

    with {:ok, code} <- bundle(entry, file),
         {:ok, _} <- QuickBEAM.eval(runtime, code) do
      :ok
    else
      {:error, %{__exception__: true} = error} -> {:error, Exception.message(error)}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp bundle(entry, file) do
    config = Volt.Config.build()

    result =
      Volt.Builder.bundle(
        entry: EntryPlugin.entry_specifier(),
        plugins: [
          {EntryPlugin, entry_id: Path.rootname(file) <> ".phoenix-vapor-fold.js", source: entry}
          | config.plugins
        ],
        aliases: config.aliases,
        node_modules: find_node_modules(Path.dirname(file)),
        name: "fold",
        minify: true,
        sourcemap: false,
        code_splitting: false,
        define: %{
          "process.env.NODE_ENV" => ~s("production"),
          "__VUE_OPTIONS_API__" => "true",
          "__VUE_PROD_DEVTOOLS__" => "false",
          "__VUE_PROD_HYDRATION_MISMATCH_DETAILS__" => "false"
        }
      )

    case result do
      {:ok, bundle} -> {:ok, bundle.code}
      error -> error
    end
  end

  defp find_node_modules(dir) do
    candidate = Path.join(dir, "node_modules")

    cond do
      File.dir?(candidate) -> candidate
      dir == "/" -> nil
      true -> find_node_modules(Path.dirname(dir))
    end
  end
end
