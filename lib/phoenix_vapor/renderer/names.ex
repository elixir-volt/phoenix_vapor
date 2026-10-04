defmodule PhoenixVapor.Renderer.Names do
  @moduledoc false

  # Atoms for names the developer declared in templates and `<script setup>`,
  # created while compiling them. Rendering never creates atoms: it looks names
  # up with `existing/1`.

  @spec atom!(String.t()) :: atom()
  def atom!(name) when is_binary(name), do: String.to_atom(name)

  # The atom for a name if one exists, otherwise the name itself. Assign keys
  # are atoms that exist, so a lookup never needs to create one.
  @spec existing(String.t()) :: atom() | String.t()
  def existing(name) when is_binary(name) do
    String.to_existing_atom(name)
  rescue
    ArgumentError -> name
  end

  @doc "Vue's `camelize`: a `side-offset` attribute is the `sideOffset` prop."
  @spec camelize(String.t()) :: String.t()
  def camelize(name) do
    [first | rest] = String.split(name, "-")
    IO.iodata_to_binary([first | Enum.map(rest, &upcase_first/1)])
  end

  defp upcase_first(<<char::utf8, rest::binary>>), do: String.upcase(<<char::utf8>>) <> rest
  defp upcase_first(""), do: ""
end
