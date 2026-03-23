defmodule Mix.Tasks.PhoenixVapor.Bundle do
  @shortdoc "Bundle Vue + npm dependencies for PhoenixVapor.LiveVue"
  @moduledoc """
  Bundles JavaScript dependencies for server-side Vue rendering.

  Uses Volt's builder to resolve imports from `node_modules/` (installed
  via `mix npm.install`), compile TypeScript, and produce a single IIFE
  bundle for QuickBEAM.

      mix phoenix_vapor.bundle

  ## Options

    * `--entry` — entry file (default: `assets/reka-entry.js`)
    * `--outdir` — output directory (default: `priv/js`)
    * `--name` — output filename without extension (default: derived from entry)
    * `--minify` / `--no-minify` — minify output (default: `true`)
  """

  use Mix.Task

  @impl true
  def run(args) do
    unless Code.ensure_loaded?(Volt.Builder) do
      Mix.raise("Volt is required for bundling. Add {:volt, \"~> 0.2.0\"} to your deps.")
    end

    {parsed, _, _} =
      OptionParser.parse(args,
        strict: [entry: :string, outdir: :string, name: :string, minify: :boolean]
      )

    entry = Keyword.get(parsed, :entry, "assets/reka-entry.js")
    outdir = Keyword.get(parsed, :outdir, "priv/js")
    _minify = Keyword.get(parsed, :minify, true)
    name = Keyword.get(parsed, :name)

    unless File.regular?(entry) do
      Mix.raise("Entry file not found: #{entry}")
    end

    node_modules = find_node_modules()

    unless node_modules do
      Mix.raise("node_modules/ not found. Run `mix npm.install` first.")
    end

    Mix.shell().info("Bundling #{entry}...")

    case Volt.Builder.build(
           entry: entry,
           outdir: outdir,
           node_modules: node_modules,
           name: name,
           minify: true,
           sourcemap: false,
           hash: false,
           code_splitting: false,

           define: %{
             "__VUE_OPTIONS_API__" => "false",
             "__VUE_PROD_DEVTOOLS__" => "false",
             "__VUE_PROD_HYDRATION_MISMATCH_DETAILS__" => "false",
             "process.env.NODE_ENV" => ~s("production")
           }
         ) do
      {:ok, result} ->
        Mix.shell().info("  #{Path.basename(result.js.path)}  #{format_size(result.js.size)}")

        if result.css do
          Mix.shell().info("  #{Path.basename(result.css.path)}  #{format_size(result.css.size)}")
        end

        Mix.shell().info("Built in #{outdir}/")

      {:error, errors} ->
        Mix.raise("Bundle failed: #{inspect(errors)}")
    end
  end

  defp find_node_modules do
    path = Path.join(File.cwd!(), "node_modules")
    if File.dir?(path), do: path
  end

  defp format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes), do: "#{Float.round(bytes / 1024, 1)} KB"
end
