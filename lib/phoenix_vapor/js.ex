defmodule PhoenixVapor.JS do
  @moduledoc false
  # A QuickBEAM runtime, or a lighter context on a `QuickBEAM.ContextPool` when
  # a pool is configured.

  @type t :: {:runtime | :context, pid()}

  @spec start(atom() | pid() | nil, keyword()) :: {:ok, t()} | {:error, term()}
  def start(pool, opts \\ [])

  def start(nil, opts) do
    with {:ok, pid} <- QuickBEAM.start(opts), do: {:ok, {:runtime, pid}}
  end

  def start(pool, opts) do
    with {:ok, pid} <- QuickBEAM.Context.start_link([pool: pool] ++ opts),
         do: {:ok, {:context, pid}}
  end

  @spec eval(t(), String.t()) :: {:ok, term()} | {:error, term()}
  def eval({:runtime, pid}, code), do: QuickBEAM.eval(pid, code)
  def eval({:context, pid}, code), do: QuickBEAM.Context.eval(pid, code)

  @spec call(t(), String.t(), list()) :: {:ok, term()} | {:error, term()}
  def call({:runtime, pid}, fun, args), do: QuickBEAM.call(pid, fun, args)
  def call({:context, pid}, fun, args), do: QuickBEAM.Context.call(pid, fun, args)

  @spec stop(t()) :: :ok
  def stop({:runtime, pid}), do: QuickBEAM.stop(pid)
  def stop({:context, pid}), do: QuickBEAM.Context.stop(pid)

  @doc "An edit for `OXC.patch_string/2`: replace bytes `start` to `stop` with `change`."
  @spec patch(non_neg_integer(), non_neg_integer(), String.t()) :: map()
  def patch(start, stop, change), do: %{start: start, end: stop, change: change}

  @doc """
  Splices for a `priv/ts` template that imports modules: an `import * as`
  statement for each source, for `$imports`, and the namespaces by source, for
  `$modules`.
  """
  @spec module_splices([String.t()]) :: {[String.t()], [String.t()]}
  def module_splices(sources) do
    sources
    |> Enum.with_index()
    |> Enum.map(fn {source, i} ->
      {"import * as m#{i} from #{Jason.encode!(source)};", "#{Jason.encode!(source)}: m#{i}"}
    end)
    |> Enum.unzip()
  end

  @doc """
  Renders a template from `priv/ts`: `binds` replaces `$name` identifiers, with
  `{:literal, value}` or `{:expr, source}` (see `OXC.bind/2`), and `splices`
  replaces `$name` statements or properties (see `OXC.splice/3`).
  """
  @spec template!(String.t(), keyword(), keyword()) :: String.t()
  def template!(relative, binds, splices) do
    source = Volt.Priv.read!({:phoenix_vapor, "ts"}, relative)

    source
    |> OXC.parse!(relative)
    |> OXC.bind(binds)
    |> then(&Enum.reduce(splices, &1, fn {name, items}, ast -> OXC.splice(ast, name, items) end))
    |> OXC.codegen!()
  end

  @doc """
  Bundles TypeScript or JavaScript `source` with Volt as if it were a module
  beside `file`, so its imports resolve from that file's `node_modules` and
  through the project's Volt aliases, as the browser build resolves them.
  Other options go to `Volt.Builder.bundle/1`.
  """
  @spec bundle(String.t(), Path.t(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def bundle(source, file, opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, "entry")
    {plugins, opts} = Keyword.pop(opts, :plugins, [])
    entry_id = Path.rootname(file) <> ".phoenix-vapor-#{name}.ts"
    config = Volt.Config.build()

    result =
      Volt.Builder.bundle(
        [
          entry: PhoenixVapor.LiveVue.EntryPlugin.entry_specifier(),
          plugins:
            [{PhoenixVapor.LiveVue.EntryPlugin, entry_id: entry_id, source: source} | plugins] ++
              config.plugins,
          aliases: config.aliases,
          node_modules: find_node_modules(Path.dirname(file)),
          name: name,
          sourcemap: false,
          code_splitting: false
        ] ++ opts
      )

    case result do
      {:ok, bundle} -> {:ok, bundle.code}
      {:error, reason} -> {:error, error_message(reason)}
    end
  end

  @doc false
  # A readable message for an error from bundling or from QuickBEAM.
  @spec error_message(term()) :: String.t()
  def error_message(reason) when is_binary(reason), do: reason
  def error_message(%{__exception__: true} = error), do: Exception.message(error)

  def error_message({:not_found, specifier}),
    do: "can't find #{inspect(specifier)}; is it installed in node_modules?"

  def error_message(reason), do: inspect(reason)

  defp find_node_modules(dir) do
    candidate = Path.join(dir, "node_modules")

    cond do
      File.dir?(candidate) -> candidate
      dir == "/" -> nil
      true -> find_node_modules(Path.dirname(dir))
    end
  end
end
