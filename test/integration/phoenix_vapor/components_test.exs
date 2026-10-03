defmodule PhoenixVapor.Integration.ComponentsTest do
  use ExUnit.Case, async: true

  defmodule PageLive do
    use Phoenix.LiveView
    use PhoenixVapor, file: "../../fixtures/components/Page.vue"
  end

  defp html(rendered), do: rendered |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()

  defp render_page(assigns),
    do: PageLive.render(Map.merge(%{name: "Ada", busy: false}, assigns)) |> html()

  describe "components imported from .vue files" do
    test "render their templates with props and slot content" do
      html = render_page(%{})

      assert html =~ ~s(<section class="card"><h3 class="card-title">Ada</h3>)
      assert html =~ "Save Ada"
    end

    test "render slot fallback content when no slot is passed" do
      assert render_page(%{}) =~
               ~s(<button type="button" class="btn btn-solid btn-md">Button</button>)
    end

    test "pass scoped slot props to slot content" do
      assert render_page(%{}) =~ "<footer>3 items</footer>"
    end

    test "merge fallthrough attributes into the root element" do
      html = render_page(%{})

      # `class` combines, `type` replaces the root's own, and `@click` becomes
      # a LiveView event.
      assert html =~
               ~s(<button type="submit" class="btn btn-ghost btn-sm w-full" phx-click="save">Save Ada</button>)
    end

    test "render boolean attributes as Vue does" do
      assert render_page(%{busy: true}) =~
               ~s(class="btn btn-ghost btn-sm w-full" disabled phx-click)

      refute render_page(%{busy: false}) =~ "disabled"
    end

    test "re-render when an assign used only in slot content changes" do
      rendered = PageLive.render(%{name: "Ada", busy: false, __changed__: %{busy: true}})
      [main] = rendered.dynamic.(true)

      assert %Phoenix.LiveView.Rendered{} = main
    end
  end

  describe "macros" do
    test "fold calls with constant arguments at compile time" do
      {split, _files, []} =
        PhoenixVapor.Components.compile(~S|<Button variant="ghost" />|,
          file: Path.expand("../../fixtures/components/Page.vue", __DIR__),
          script: ~s(import Button from "./Button.vue")
        )

      [%{component: %{split: button}}] = split.slots
      [%{kind: :root_attrs, props: props} | _] = button.slots

      assert {"class", [{:value, "btn btn-ghost btn-md"}]} in Enum.map(
               props,
               &{&1.key, &1.values}
             )
    end

    test "report calls whose arguments are only known when rendering" do
      error =
        assert_raise CompileError, fn ->
          defmodule DynamicMacroLive do
            use Phoenix.LiveView
            use PhoenixVapor, file: "../../fixtures/components/DynamicMacro.vue"
          end
        end

      assert Exception.message(error) =~
               "`button({ variant: props.variant, size: props.size })` calls a macro with values known only when rendering"
    end
  end

  test "a component from a package is a compile error outside hybrid mode" do
    error =
      assert_raise CompileError, fn ->
        defmodule PackageComponentLive do
          use Phoenix.LiveView
          use PhoenixVapor, file: "../../fixtures/components/PackageComponent.vue"
        end
      end

    assert Exception.message(error) =~
             ~s(<DialogRoot> from "reka-ui", which the server can't render)
  end
end
