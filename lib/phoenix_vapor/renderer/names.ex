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
end
