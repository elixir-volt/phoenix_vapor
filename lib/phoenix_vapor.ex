defmodule PhoenixVapor do
  @moduledoc """
  Vue templates as native LiveView rendered structs.

  Compiles Vue template syntax to `%Phoenix.LiveView.Rendered{}` via
  Vize's Vapor IR. Simple expressions evaluate in pure Elixir via OXC AST;
  complex JS expressions fall back to QuickBEAM when available.

  ## Sigil Usage

      import PhoenixVapor.Sigil

      def dashboard(assigns) do
        ~VUE\"""
        <div :class="status">
          <h1>{{ title }}</h1>
          <ul>
            <li v-for="item in items">{{ item.name }}</li>
          </ul>
        </div>
        \"""
      end

  ## Programmatic Usage

      def dashboard(assigns) do
        PhoenixVapor.render(
          "<div :class=\\"status\\"><h1>{{ title }}</h1></div>",
          assigns
        )
      end

  Or precompile the split at compile time:

      @split Vize.vapor_split!("<div :class=\\"status\\"><h1>{{ title }}</h1></div>")

      def dashboard(assigns) do
        PhoenixVapor.render(@split, assigns)
      end
  """

  alias PhoenixVapor.Renderer
  alias PhoenixVapor.VaporRenderer

  defmacro __using__(_opts) do
    quote do
      import PhoenixVapor.Sigil
      import PhoenixVapor.Component
    end
  end

  @doc """
  Render a Vue template as a `%Phoenix.LiveView.Rendered{}` struct.

  Accepts either a template string (compiled on the fly) or a
  pre-compiled split map from `Vize.vapor_split/1`.
  """
  @spec render(String.t() | map(), map()) :: Phoenix.LiveView.Rendered.t()
  def render(template, assigns) when is_binary(template) do
    render(Vize.vapor_split!(template), assigns)
  end

  def render(%{statics: _, slots: _} = split, assigns) do
    Renderer.to_rendered(split, assigns)
  end

  @doc """
  Render a Vue template as a `%Phoenix.LiveView.VaporRendered{}` struct.

  Uses the first-class Vapor render mode — schema-driven direct DOM
  patching with explicit slot, branch, and list semantics.

  Accepts either a template string or a pre-compiled split map.
  """
  @spec vapor_render(String.t() | map(), map()) :: Phoenix.LiveView.VaporRendered.t()
  def vapor_render(template, assigns) when is_binary(template) do
    vapor_render(Vize.vapor_split!(template), assigns)
  end

  def vapor_render(%{statics: _, slots: _} = split, assigns) do
    VaporRenderer.to_vapor_rendered(split, assigns)
  end
end
