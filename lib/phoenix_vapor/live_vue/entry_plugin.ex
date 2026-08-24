defmodule PhoenixVapor.LiveVue.EntryPlugin do
  @moduledoc false

  @behaviour Volt.Plugin

  @entry_specifier "virtual:phoenix-vapor/live-vue-entry"

  @impl true
  def name, do: "phoenix-vapor-live-vue-entry"

  @impl true
  def enforce, do: :pre

  def entry_specifier, do: @entry_specifier

  def entry_id(sfc_path) do
    Path.rootname(sfc_path) <> ".phoenix-vapor.js"
  end

  def resolve(@entry_specifier, nil, opts), do: {:ok, Keyword.fetch!(opts, :entry_id)}
  def resolve(_specifier, _importer, _opts), do: nil

  def load(path, opts) do
    if path == Keyword.fetch!(opts, :entry_id) do
      {:ok, Keyword.fetch!(opts, :source)}
    end
  end
end
