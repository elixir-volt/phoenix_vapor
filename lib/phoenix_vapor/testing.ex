defmodule PhoenixVapor.Testing do
  @moduledoc """
  Helpers for testing PhoenixVapor rendered output.
  """

  @doc """
  Renders a LiveView rendered struct or comprehension to an HTML string.
  """
  @spec render_to_html(
          Phoenix.LiveView.Rendered.t()
          | Phoenix.LiveView.Comprehension.t()
          | term()
        ) :: String.t()
  def render_to_html(%Phoenix.LiveView.Rendered{} = rendered) do
    dynamic = rendered.dynamic.(false)

    rendered.static
    |> Enum.with_index()
    |> Enum.map(fn {static, index} ->
      case Enum.at(dynamic, index) do
        nil ->
          static

        %Phoenix.LiveView.Rendered{} = nested ->
          static <> render_to_html(nested)

        %Phoenix.LiveView.Comprehension{} = comprehension ->
          static <> render_to_html(comprehension)

        value ->
          static <> to_string(value)
      end
    end)
    |> IO.iodata_to_binary()
  end

  def render_to_html(%Phoenix.LiveView.Comprehension{} = comprehension) do
    comprehension.entries
    |> Enum.map(fn {_key, _vars, render} ->
      dynamic = render.(%{}, false)

      comprehension.static
      |> Enum.with_index()
      |> Enum.map(fn {static, index} ->
        case Enum.at(dynamic, index) do
          nil -> static
          %Phoenix.LiveView.Rendered{} = nested -> static <> render_to_html(nested)
          %Phoenix.LiveView.Comprehension{} = nested -> static <> render_to_html(nested)
          value -> static <> to_string(value)
        end
      end)
    end)
    |> IO.iodata_to_binary()
  end

  def render_to_html(value), do: to_string(value)

  @doc """
  Returns the static fragments from a rendered struct.
  """
  @spec static_values(Phoenix.LiveView.Rendered.t()) :: [String.t()]
  def static_values(%Phoenix.LiveView.Rendered{static: static}), do: static

  @doc """
  Returns the dynamic values from a rendered struct with change tracking disabled.
  """
  @spec dynamic_values(Phoenix.LiveView.Rendered.t()) :: [term()]
  def dynamic_values(%Phoenix.LiveView.Rendered{} = rendered), do: rendered.dynamic.(false)

  @doc """
  Extracts the hybrid component name from rendered HTML.
  """
  @spec hybrid_component(Phoenix.LiveView.Rendered.t() | String.t()) :: String.t() | nil
  def hybrid_component(rendered_or_html) do
    rendered_or_html
    |> html_for_extract()
    |> extract_attr("data-pv-client")
  end

  @doc """
  Extracts decoded hybrid props from rendered HTML.

  Supports both the legacy raw props payload and the structured envelope. For
  envelope payloads, this returns the nested `"props"` map.
  """
  @spec hybrid_props(Phoenix.LiveView.Rendered.t() | String.t()) :: map() | nil
  def hybrid_props(rendered_or_html) do
    case hybrid_envelope(rendered_or_html) do
      %{"props" => props} when is_map(props) -> props
      props when is_map(props) -> props
      _ -> nil
    end
  end

  @doc """
  Extracts the raw decoded hybrid prop envelope from rendered HTML.
  """
  @spec hybrid_envelope(Phoenix.LiveView.Rendered.t() | String.t()) :: map() | nil
  def hybrid_envelope(rendered_or_html) do
    rendered_or_html
    |> html_for_extract()
    |> extract_attr("data-pv-props")
    |> case do
      nil -> nil
      json -> Jason.decode!(html_unescape(json))
    end
  end

  defp html_for_extract(%Phoenix.LiveView.Rendered{} = rendered), do: render_to_html(rendered)
  defp html_for_extract(html) when is_binary(html), do: html

  defp extract_attr(html, attr) do
    marker = attr <> "=\""

    case String.split(html, marker, parts: 2) do
      [_, rest] -> rest |> String.split("\"", parts: 2) |> hd()
      _ -> nil
    end
  end

  defp html_unescape(value) do
    value
    |> String.replace("&quot;", ~s("))
    |> String.replace("&#39;", "'")
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
  end
end
