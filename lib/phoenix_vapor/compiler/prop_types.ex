defmodule PhoenixVapor.Compiler.PropTypes do
  @moduledoc false

  # The values a component's props can take, from TypeScript's own checker,
  # for macro calls that read props known only when rendering. A prop typed as
  # a finite set of literals, such as `"sm" | "md"`, `boolean`, or a variant
  # type derived from a tailwind-variants config, lets the macro run once per
  # value at compile time.
  #
  # TypeScript comes from the project's `node_modules`, as `vue-tsc` and
  # editors use it, and runs in a QuickBEAM runtime of its own, one per
  # TypeScript install, which compiles in the same VM share: loading it takes
  # over a second, a check a few milliseconds. It reads the project's files
  # through `handlers/0`, and keeps those it parsed until they change. See
  # `PropTypes.Runtime` for how long it lives.

  alias NPM.Resolution.PackageResolver
  alias PhoenixVapor.Compiler.PropTypes.Runtime

  @doc "The QuickBEAM handlers TypeScript reads files through."
  @spec handlers() :: %{String.t() => ([term()] -> term())}
  def handlers do
    %{
      "read" => fn [path] ->
        case File.read(path) do
          {:ok, text} -> text
          {:error, _reason} -> nil
        end
      end,
      "file?" => fn [path] -> File.regular?(path) end,
      "mtime" => fn [path] ->
        case File.stat(path, time: :posix) do
          {:ok, %{mtime: mtime}} -> mtime
          {:error, _reason} -> nil
        end
      end,
      "dir?" => fn [path] -> File.dir?(path) end
    }
  end

  @doc """
  The values each of `props` can take, as `defineProps<T>()` in `script`
  declares them, with nil for a prop whose type isn't a finite set of literals.
  `undefined` and `null` are both nil.
  """
  @spec literal_values(Path.t(), String.t(), [String.t()]) ::
          {:ok, %{String.t() => [term()] | nil}} | {:error, String.t()}
  def literal_values(file, script, props),
    do: call(file, "__pv_literal_values", [script, props])

  @doc """
  The values each of `expressions`, template expressions of the component
  `script` sets up, can take, in order: `%{"values" => values, "type" =>
  type}`, where values is nil for an expression whose type isn't a finite set
  of literals, and type is how TypeScript writes it. The expressions read the
  script's bindings as the template does, refs and models unwrapped, and the
  props `defineProps<T>()` declares.
  """
  @spec expression_values(Path.t(), String.t(), [String.t()]) ::
          {:ok, [%{String.t() => term()}]} | {:error, String.t()}
  def expression_values(file, script, expressions),
    do: call(file, "__pv_expression_values", [script, expressions])

  defp call(file, function, [script, names]) do
    with {:ok, main} <- typescript(file),
         {:ok, runtime} <- Runtime.fetch(main, &load(&1, main, file)) do
      args = [file <> ".ts", script, names, Path.dirname(main)]

      case QuickBEAM.call(runtime, function, args) do
        {:ok, values} -> {:ok, values}
        {:error, error} -> {:error, PhoenixVapor.JS.error_message(error)}
      end
    end
  end

  # Loads TypeScript as published, which defines the global `ts`, then
  # `compile/prop-types.ts` against it.
  defp load(runtime, main, file) do
    with {:ok, _} <- QuickBEAM.eval(runtime, File.read!(main)),
         {:ok, code} <-
           PhoenixVapor.JS.bundle(
             Volt.Priv.read!({:phoenix_vapor, "ts"}, "compile/prop-types.ts"),
             file,
             name: "prop-types",
             minify: false,
             external: %{"typescript" => "ts"}
           ),
         {:ok, _} <- QuickBEAM.eval(runtime, code) do
      :ok
    else
      {:error, reason} -> {:error, PhoenixVapor.JS.error_message(reason)}
    end
  end

  # TypeScript's CommonJS entry, from the nearest ancestor directory whose
  # `node_modules` has it, as Node resolves packages, or the project's.
  defp typescript(file) do
    file
    |> Path.dirname()
    |> Stream.unfold(fn dir -> if dir, do: {dir, parent(dir)} end)
    |> Stream.concat([File.cwd!()])
    |> Stream.map(&Path.join([&1, "node_modules", "typescript"]))
    |> Enum.find(&File.dir?/1)
    |> case do
      nil ->
        {:error, "TypeScript isn't installed; add `typescript` to package.json"}

      dir ->
        case PackageResolver.resolve_entry(dir, conditions: ["require", "default"]) do
          {:ok, main} -> {:ok, main}
          :error -> {:error, "can't find TypeScript's entry in #{dir}"}
        end
    end
  end

  defp parent(dir) do
    parent = Path.dirname(dir)
    if parent != dir, do: parent
  end
end
