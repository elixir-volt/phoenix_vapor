defmodule PhoenixVapor.JS.EntryPlugin do
  @moduledoc false

  # Serves `PhoenixVapor.JS.bundle/3`'s generated source as the bundle's entry
  # module, under `:entry_id`, a path beside the file it's bundled for, so its
  # imports resolve from there.

  @behaviour Volt.Plugin

  @entry_specifier "virtual:phoenix-vapor/entry"

  @impl true
  def name, do: "phoenix-vapor-entry"

  @impl true
  def enforce, do: :pre

  def entry_specifier, do: @entry_specifier

  def resolve(@entry_specifier, nil, opts), do: {:ok, Keyword.fetch!(opts, :entry_id)}
  def resolve(_specifier, _importer, _opts), do: nil

  def load(path, opts) do
    if path == Keyword.fetch!(opts, :entry_id) do
      {:ok, Keyword.fetch!(opts, :source)}
    end
  end
end
