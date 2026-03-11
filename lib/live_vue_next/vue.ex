defmodule LiveVueNext.Vue do
  @moduledoc """
  Load Vue Single File Components (`.vue` files) as LiveView function components.

  ## Usage

      defmodule MyAppWeb.Components do
        use Phoenix.Component

        LiveVueNext.Vue.component :card, "assets/vue/Card.vue"
        LiveVueNext.Vue.component :dashboard, "assets/vue/Dashboard.vue"
      end

  This compiles the Vue template at compile time via `Vize.vapor_ir!/1`
  and generates a function component that renders the IR against assigns.

  The SFC's `<template>` block is extracted and compiled. `<script>` and
  `<style>` blocks are currently ignored (see LiveVueNext roadmap for
  QuickBEAM integration plans).
  """

  @doc """
  Define a function component from a `.vue` file's template.

  The file is read and the template is compiled at compile time.
  """
  defmacro component(name, path) do
    caller_dir = __CALLER__.file |> Path.dirname()
    full_path = Path.expand(path, caller_dir)

    source = File.read!(full_path)
    template = extract_template(source)
    ir = Vize.vapor_ir!(template)
    escaped_ir = Macro.escape(ir)

    quote do
      def unquote(name)(var!(assigns)) do
        LiveVueNext.Renderer.to_rendered(unquote(escaped_ir), var!(assigns))
      end
    end
  end

  @doc false
  def extract_template(sfc_source) do
    case Regex.run(~r/<template>([\s\S]*?)<\/template>/, sfc_source) do
      [_, template] -> String.trim(template)
      nil -> sfc_source
    end
  end
end
