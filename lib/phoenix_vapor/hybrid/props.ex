defmodule PhoenixVapor.Hybrid.Props do
  @moduledoc false

  alias PhoenixVapor.Prop

  @envelope_version 1
  @skip :__phoenix_vapor_skip_prop__

  def build_envelope(assigns, client_props, opts \\ []) do
    {props, full?} = props_for_envelope(assigns, client_props, opts)

    envelope = %{
      version: @envelope_version,
      component: opts[:component],
      clientVersion: opts[:client_version],
      full: full?,
      props: props
    }

    envelope
    |> maybe_put_deferred_props(assigns, client_props)
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  def encode_envelope!(envelope), do: Jason.encode!(envelope)

  def collect_props(assigns, client_props) do
    Enum.reduce(client_props, %{}, fn prop, acc ->
      output_key = output_key(prop)

      case prop_value(assigns, prop) do
        @skip -> acc
        value -> Map.put(acc, output_key, value)
      end
    end)
  end

  defp props_for_envelope(assigns, client_props, opts) do
    changed = Map.get(assigns, :__changed__)

    if opts[:partial] && is_map(changed) do
      {collect_props(assigns, changed_client_props(assigns, client_props, changed)), false}
    else
      {collect_props(assigns, client_props), true}
    end
  end

  defp changed_client_props(assigns, client_props, changed) do
    Enum.filter(client_props, &prop_changed?(assigns, &1, changed))
  end

  defp prop_changed?(assigns, prop, changed) do
    atom_key = atom_key(prop)
    string_key = output_key(prop)

    Map.has_key?(changed, atom_key) || Map.has_key?(changed, string_key) ||
      advanced_prop_changed?(assigns, prop, changed)
  end

  defp advanced_prop_changed?(assigns, prop, changed) do
    assigns
    |> advanced_props()
    |> Enum.any?(fn {key, _value} ->
      output_key(key) == output_key(prop) &&
        (Map.has_key?(changed, key) || Map.has_key?(changed, output_key(key)))
    end)
  end

  defp prop_value(assigns, prop) do
    advanced = advanced_props(assigns)

    case fetch_advanced_prop(advanced, prop) do
      {:ok, value} -> resolve_prop_value(value)
      :error -> Map.get(assigns, atom_key(prop), Map.get(assigns, output_key(prop)))
    end
  end

  defp resolve_prop_value(%Prop.Always{value: value}), do: value
  defp resolve_prop_value(%Prop.Optional{}), do: @skip
  defp resolve_prop_value(%Prop.Defer{}), do: @skip
  defp resolve_prop_value(value), do: value

  defp fetch_advanced_prop(advanced, prop) do
    Enum.find_value(advanced, :error, fn {key, value} ->
      if output_key(key) == output_key(prop), do: {:ok, value}, else: false
    end)
  end

  defp advanced_props(assigns), do: Map.get(assigns, :__pv_props__, %{})

  defp output_key({:preserve, key}), do: to_string(key)
  defp output_key(key), do: to_string(key)

  defp maybe_put_deferred_props(envelope, assigns, client_props) do
    deferred_props = deferred_props(assigns, client_props)

    if map_size(deferred_props) == 0 do
      envelope
    else
      Map.put(envelope, :deferredProps, deferred_props)
    end
  end

  defp deferred_props(assigns, client_props) do
    client_prop_keys = MapSet.new(Enum.map(client_props, &output_key/1))

    assigns
    |> advanced_props()
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      output = output_key(key)

      case value do
        %Prop.Defer{group: group} ->
          if MapSet.member?(client_prop_keys, output) do
            Map.update(acc, group, [output], &[output | &1])
          else
            acc
          end

        _ ->
          acc
      end
    end)
    |> Map.new(fn {group, keys} -> {group, Enum.reverse(keys)} end)
  end

  def resolve_deferred(socket, group) do
    {resolved, remaining} =
      socket.assigns
      |> advanced_props()
      |> Enum.reduce({%{}, %{}}, fn {key, value}, {resolved, remaining} ->
        case value do
          %Prop.Defer{fun: fun, group: ^group} ->
            {Map.put(resolved, atom_key(key), fun.()), remaining}

          _ ->
            {resolved, Map.put(remaining, key, value)}
        end
      end)

    socket = Phoenix.Component.assign(socket, :__pv_props__, remaining)

    Enum.reduce(resolved, socket, fn {key, value}, acc ->
      Phoenix.Component.assign(acc, key, value)
    end)
  end

  defp atom_key({:preserve, key}), do: atom_key(key)
  defp atom_key(key) when is_atom(key), do: key
  defp atom_key(key) when is_binary(key), do: String.to_atom(key)
end
