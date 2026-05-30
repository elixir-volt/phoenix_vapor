defmodule PhoenixVapor.Errors do
  @moduledoc """
  Converts validation error data into a shape that is convenient for Vapor components.

  Maps are validated and returned as-is. Ecto changesets are supported when Ecto
  is available in the host application.
  """

  @type errors :: %{optional(atom() | String.t()) => String.t() | errors()}
  @type msg_func :: ({String.t(), keyword()} -> String.t())

  @doc """
  Converts validation data into a flat error map.
  """
  @spec to_errors(term()) :: map()
  def to_errors(value), do: to_errors(value, &default_msg_func/1)

  @doc """
  Converts validation data into a flat error map using a custom changeset message function.
  """
  @spec to_errors(term(), msg_func()) :: map()
  def to_errors(%{__struct__: Ecto.Changeset} = changeset, msg_func) do
    if Code.ensure_loaded?(Ecto.Changeset) do
      Ecto.Changeset
      |> apply(:traverse_errors, [changeset, msg_func])
      |> process_changeset_errors()
      |> Map.new()
    else
      raise ArgumentError, "Ecto.Changeset errors require Ecto to be available"
    end
  end

  def to_errors(map, _msg_func) when is_map(map) do
    validate_error_map!(map)
  end

  def to_errors(value, _msg_func) do
    raise ArgumentError, "expected an error map or Ecto.Changeset, got #{inspect(value)}"
  end

  defp process_changeset_errors(value, path \\ nil)

  defp process_changeset_errors(%{} = map, path) do
    map
    |> Map.to_list()
    |> Enum.flat_map(fn {key, value} ->
      next_path = if path, do: "#{path}.#{key}", else: to_string(key)
      List.wrap(process_changeset_errors(value, next_path))
    end)
  end

  defp process_changeset_errors([%{} | _] = maps, path) do
    maps
    |> Enum.with_index()
    |> Enum.flat_map(fn {map, index} ->
      process_changeset_errors(map, "#{path}[#{index}]")
    end)
  end

  defp process_changeset_errors([message | _], path) when is_binary(message) do
    {path, message}
  end

  defp process_changeset_errors([], _path), do: []

  defp default_msg_func({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end

  defp validate_error_map!(map) do
    values = Map.values(map)

    if Enum.all?(values, &is_map/1) do
      Enum.each(values, &validate_error_map!/1)
    else
      Enum.each(map, fn {key, value} ->
        unless is_atom(key) or is_binary(key) do
          raise ArgumentError, "expected atom or string key, got #{inspect(key)}"
        end

        unless is_binary(value) do
          raise ArgumentError,
                "expected string value for #{to_string(key)}, got #{inspect(value)}"
        end
      end)
    end

    map
  end
end
