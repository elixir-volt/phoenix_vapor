defmodule PhoenixVapor.Volt do
  @moduledoc """
  A [Volt](https://hexdocs.pm/volt) plugin that resolves `phoenix_vapor`
  imports, such as `phoenix_vapor/hybrid`, from wherever Mix put the
  dependency, through the package's own `exports`.

  `resolve_dirs: ["deps"]` finds a Hex dependency under `deps/`. A path or
  umbrella dependency lives elsewhere, so add the plugin:

      config :volt,
        plugins: [PhoenixVapor.Volt]
  """

  @behaviour Volt.Plugin

  alias NPM.Resolution.PackageResolver

  @impl true
  def name, do: "phoenix-vapor"

  @impl true
  def resolve("phoenix_vapor", _importer), do: export(".")
  def resolve("phoenix_vapor/" <> subpath, _importer), do: export("./" <> subpath)
  def resolve(_specifier, _importer), do: nil

  defp export(subpath) do
    case PackageResolver.resolve_entry(package_dir(), subpath: subpath) do
      {:ok, path} -> {:ok, path}
      :error -> nil
    end
  end

  # The dependency's directory, or the project's own when PhoenixVapor builds
  # its tests.
  defp package_dir do
    case Mix.Project.config()[:app] do
      :phoenix_vapor -> File.cwd!()
      _app -> Map.fetch!(Mix.Project.deps_paths(), :phoenix_vapor)
    end
  end
end
