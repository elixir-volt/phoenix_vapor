defmodule PhoenixVapor.Vue do
  @moduledoc """
  Load Vue Single File Components (`.vue` files) as LiveView function components.

  ## Usage

      defmodule MyAppWeb.Components do
        use Phoenix.Component

        PhoenixVapor.Vue.component :card, "assets/vue/Card.vue"
        PhoenixVapor.Vue.component :dashboard, "assets/vue/Dashboard.vue"
      end

  This compiles the Vue template at compile time via `Vize.vapor_ir!/1`
  and generates a function component that renders the IR against assigns.

  The SFC's `<template>` block is extracted and compiled. `<script>` and
  `<style>` blocks are currently ignored (see PhoenixVapor roadmap for
  QuickBEAM integration plans).
  """

  @doc """
  Define a function component from a `.vue` file's template.

  Supports `<style scoped>` — generates scoped CSS and injects
  the `data-v-*` scope attribute into the root element.
  """
  defmacro component(name, path) do
    caller_dir = __CALLER__.file |> Path.dirname()
    full_path = Path.expand(path, caller_dir)

    source = File.read!(full_path)
    template = extract_template(source)
    split = Vize.vapor_split!(template)
    escaped_split = Macro.escape(split)

    {scope_id, scoped_css} = extract_scoped_css(source)

    css_fn_name = :"__vue_css_#{name}__"

    quote do
      def unquote(css_fn_name)(), do: unquote(scoped_css)

      def unquote(name)(var!(assigns)) do
        rendered = PhoenixVapor.Renderer.to_rendered(unquote(escaped_split), var!(assigns))

        if unquote(scope_id) do
          PhoenixVapor.Renderer.inject_scope_id(rendered, unquote(scope_id))
        else
          rendered
        end
      end
    end
  end

  @doc false
  def extract_template(sfc_source) do
    case Vize.parse_sfc(sfc_source) do
      {:ok, %{template: %{content: content}}} -> String.trim(content)
      _ -> sfc_source
    end
  end

  @doc false
  def extract_scoped_css(sfc_source) do
    result = Vize.compile_sfc!(sfc_source)
    css = result.css

    if css && css != "" do
      # Scope ID is embedded in the CSS by Vize's scoped style compiler
      case Regex.run(~r/\[data-v-([a-f0-9]+)\]/, css) do
        [_, hash] -> {"data-v-#{hash}", css}
        nil -> {nil, css}
      end
    else
      {nil, nil}
    end
  end
end
