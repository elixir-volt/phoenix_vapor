defmodule LiveVueNext do
  @moduledoc """
  Vue templates as native LiveView rendered structs.

  Compiles Vue template syntax to `%Phoenix.LiveView.Rendered{}` via
  Vize's Vapor IR — no JavaScript runtime needed for template-only components.

  ## Sigil Usage

      import LiveVueNext.Sigil

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
        LiveVueNext.render(
          "<div :class=\\"status\\"><h1>{{ title }}</h1></div>",
          assigns
        )
      end

  Or precompile the IR at compile time:

      @ir Vize.vapor_ir!("<div :class=\\"status\\"><h1>{{ title }}</h1></div>")

      def dashboard(assigns) do
        LiveVueNext.render(@ir, assigns)
      end
  """

  alias LiveVueNext.Renderer

  defmacro __using__(_opts) do
    quote do
      import LiveVueNext.Sigil
      import LiveVueNext.Component
    end
  end

  @doc """
  Render a Vue template as a `%Phoenix.LiveView.Rendered{}` struct.

  Accepts either a template string (compiled on the fly via `Vize.vapor_ir!/1`)
  or a pre-compiled IR map from `Vize.vapor_ir/1`.
  """
  @spec render(String.t() | map(), map()) :: Phoenix.LiveView.Rendered.t()
  def render(template, assigns) when is_binary(template) do
    render(Vize.vapor_ir!(template), assigns)
  end

  def render(%{block: _, templates: _} = ir, assigns) do
    Renderer.to_rendered(ir, assigns)
  end
end
