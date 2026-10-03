defmodule PhoenixVapor.Sigil do
  @moduledoc """
  Provides the `~VUE` sigil for embedding Vue templates in LiveView components.

  The Vue template is compiled to a statics/slots split at compile time via
  `Vize.split_template!/1`. At runtime, slots are evaluated against assigns to
  produce a `%Phoenix.LiveView.Rendered{}` struct with per-assign change tracking.

  ## Usage

      import PhoenixVapor.Sigil

      def render(assigns) do
        ~VUE\"""
        <div :class="status">
          <h1>{{ title }}</h1>
          <ul>
            <li v-for="item in items" :key="item.id">{{ item.name }}</li>
          </ul>
          <p v-if="showFooter">{{ footerText }}</p>
        </div>
        \"""
      end

  The template has access to all keys in `assigns`. Nested access like
  `user.name` resolves via map key lookup.
  """

  @doc """
  Compile a Vue template to a LiveView `%Rendered{}` struct.

  The template is compiled at compile time. The resulting IR is embedded
  in the module's bytecode and evaluated against `assigns` at runtime.

  Requires `assigns` to be in scope (same as `~H`).
  """
  defmacro sigil_VUE({:<<>>, meta, [template]}, _modifiers) do
    # A heredoc's content starts on the line after the sigil.
    origin = {__CALLER__.line + if(meta[:indentation], do: 1, else: 0), 1}

    {split, _files} =
      PhoenixVapor.Components.compile!(template,
        file: __CALLER__.file,
        origin: origin,
        unrendered: :raise
      )

    quote do
      PhoenixVapor.Renderer.to_rendered(
        unquote(Macro.escape(split)),
        var!(assigns)
      )
    end
  end
end
