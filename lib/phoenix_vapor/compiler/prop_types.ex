defmodule PhoenixVapor.Compiler.PropTypes do
  @moduledoc false

  # The values a component's props can take, from TypeScript's own checker,
  # for macro calls that read props known only when rendering. A prop typed as
  # a finite set of literals, such as `"sm" | "md"`, `boolean`, or a variant
  # type derived from a tailwind-variants config, lets the macro run once per
  # value at compile time.
  #
  # TypeScript comes from the project's `node_modules`, as `vue-tsc` and
  # editors use it, and runs in the compile's `PhoenixVapor.JS.Session`. It reads the
  # project's files through `handlers/0`.

  alias NPM.Resolution.PackageResolver
  alias PhoenixVapor.JS.Session

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
      "dir?" => fn [path] -> File.dir?(path) end
    }
  end

  @doc """
  The values each of `props` can take, as `defineProps<T>()` in `script`
  declares them, with nil for a prop whose type isn't a finite set of literals.
  `undefined` and `null` are both nil.
  """
  @spec literal_values(Session.t(), Path.t(), String.t(), [String.t()]) ::
          {:ok, %{String.t() => [term()] | nil}} | {:error, String.t()}
  def literal_values(session, file, script, props) do
    with {:ok, main} <- typescript(file),
         :ok <- Session.once(session, {:typescript, main}, &load(&1, main, file)) do
      args = [file <> ".ts", script, props, Path.dirname(main)]

      case QuickBEAM.call(Session.runtime(session), "__pv_literal_values", args) do
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
