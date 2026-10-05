defmodule PhoenixVapor.Vue do
  @moduledoc """
  Load Vue Single File Components (`.vue` files) as LiveView function components.

  ## Usage

      defmodule MyAppWeb.Components do
        use Phoenix.Component

        PhoenixVapor.Vue.component :card, "vue/Card.vue"
        PhoenixVapor.Vue.component :dashboard, "vue/Dashboard.vue"
      end

  The path is relative to the module's file, and can be any expression known
  at compile time, such as `Path.join(@templates, "Card.vue")`.

  This compiles the Vue template at compile time via `Vize.split_template/2`
  and generates a function component that renders it against assigns.

  The SFC's `<template>` block becomes the component. A `<style scoped>`
  block is compiled and exposed as `__vue_css_<name>__/0`, and the root
  element gets its scope attribute. `<script>` blocks are ignored.
  """

  alias PhoenixVapor.Compiler.SFC

  @doc """
  Define a function component from a `.vue` file's template.

  Supports `<style scoped>` — generates scoped CSS and injects
  the `data-v-*` scope attribute into the root element.
  """
  defmacro component(name, path) do
    sfc = SFC.load!(path, __CALLER__)
    full_path = sfc.file
    {split, component_files} = PhoenixVapor.Compiler.compile!(sfc, root_attrs: true)
    escaped_split = Macro.escape(split)

    {scope_id, scoped_css} = scoped_css(sfc)

    css_fn_name = :"__vue_css_#{name}__"
    root_attrs = if scope_id, do: [{scope_id, ""}], else: []

    quote do
      @external_resource unquote(full_path)
      for file <- unquote(component_files), do: @external_resource(file)

      def unquote(css_fn_name)(), do: unquote(scoped_css)

      def unquote(name)(var!(assigns)) do
        PhoenixVapor.Renderer.to_rendered(unquote(escaped_split), var!(assigns),
          root_attrs: unquote(root_attrs)
        )
      end
    end
  end

  # Vize generates the scope id the way its bundler integrations do and
  # scopes the CSS with it; the same id goes on the root element.
  defp scoped_css(%SFC{} = sfc) do
    if Enum.any?(sfc.descriptor.styles, & &1.scoped) do
      id = Vize.SFC.scope_id(sfc.file, root: File.cwd!())
      {"data-v-#{id}", Vize.compile_sfc!(sfc.source, scope_id: id).css}
    else
      {nil, nil}
    end
  end
end
