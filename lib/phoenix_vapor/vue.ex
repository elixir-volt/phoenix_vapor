defmodule PhoenixVapor.Vue do
  @moduledoc """
  Load Vue Single File Components (`.vue` files) as LiveView function components.

  ## Usage

      defmodule MyAppWeb.Components do
        use Phoenix.Component

        PhoenixVapor.Vue.component :card, "assets/vue/Card.vue"
        PhoenixVapor.Vue.component :dashboard, "assets/vue/Dashboard.vue"
      end

  This compiles the Vue template at compile time via `Vize.split_template/2`
  and generates a function component that renders it against assigns.

  The SFC's `<template>` block becomes the component. A `<style scoped>`
  block is compiled and exposed as `__vue_css_<name>__/0`, and the root
  element gets its scope attribute. `<script>` blocks are ignored.
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
    desc = Vize.parse_sfc!(source)
    {template, origin} = PhoenixVapor.SFC.template!(desc, full_path)
    script = (desc.script_setup && desc.script_setup.content) || ""

    {split, component_files} =
      PhoenixVapor.Components.compile!(template,
        file: full_path,
        origin: origin,
        script: script,
        unrendered: :raise
      )

    escaped_split = Macro.escape(split)

    {scope_id, scoped_css} = scoped_css(source, full_path)

    css_fn_name = :"__vue_css_#{name}__"

    quote do
      @external_resource unquote(full_path)
      for file <- unquote(component_files), do: @external_resource(file)

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

  # Vize generates the scope id the way its bundler integrations do and
  # scopes the CSS with it; the same id goes on the root element.
  defp scoped_css(sfc_source, path) do
    if Enum.any?(Vize.parse_sfc!(sfc_source).styles, & &1.scoped) do
      id = Vize.SFC.scope_id(path, root: File.cwd!())
      {"data-v-#{id}", Vize.compile_sfc!(sfc_source, scope_id: id).css}
    else
      {nil, nil}
    end
  end
end
