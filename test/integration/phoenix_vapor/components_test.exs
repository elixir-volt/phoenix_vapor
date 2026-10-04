defmodule PhoenixVapor.Integration.ComponentsTest do
  use ExUnit.Case, async: true

  alias PhoenixVapor.Fixtures

  defmodule PageLive do
    use Phoenix.LiveView
    use PhoenixVapor, file: Fixtures.path("components/Page.vue")
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
          file: Fixtures.path("components/Page.vue"),
          script: ~s(import Button from "./Button.vue")
        )

      [%{component: %{template: button}}] = split.slots
      [%{kind: :root_attrs, props: props} | _] = button.slots

      assert %{name: "class", value: {:value, "btn btn-ghost btn-md"}} =
               Enum.find(props, &(&1.name == "class"))
    end

    test "report calls whose arguments are only known when rendering" do
      error =
        assert_raise CompileError, fn ->
          defmodule DynamicMacroLive do
            use Phoenix.LiveView
            use PhoenixVapor, file: Fixtures.path("components/DynamicMacro.vue")
          end
        end

      assert Exception.message(error) =~
               "`button({ variant: props.variant, size: props.size })` calls a macro with values known only when rendering"
    end
  end

  describe "package components in hybrid mode" do
    defmodule PackageFoldLive do
      use Phoenix.LiveView
      use PhoenixVapor, file: Fixtures.path("components/PackageFold.vue"), client_output: nil
    end

    test "render at compile time, with the template's content inside them" do
      html = PackageFoldLive.render(%{name: "Ada"}) |> html()

      # TooltipProvider renders only its content; the Tabs render as Reka does,
      # on the tab the ref starts on.
      assert html =~ ~s(<div dir="ltr" data-orientation="horizontal">)
      assert html =~ ~s(role="tablist")
      assert html =~ ~r/aria-selected="true" data-state="active">Greeting/
      assert html =~ ~r/role="tabpanel" data-state="active"[^>]*><p>Hello Ada<\/p><\/div>/
      refute html =~ "<p>Other</p>"
    end

    test "that need a parent they're rendered without are reported with Vue's reason" do
      {_template, _files, [diagnostic]} =
        PhoenixVapor.Components.compile(~S|<TabsList>Tabs</TabsList>|,
          file: Fixtures.path("components/PackageFold.vue"),
          script: ~s(import { TabsList } from "reka-ui"),
          fold: :all
        )

      assert %{severity: :unrendered, message: message} = diagnostic
      assert message =~ "<TabsList> from \"reka-ui\" can't render on the server"
      assert message =~ "TabsRootContext"
    end
  end

  describe "package components outside hybrid mode" do
    defmodule PackageProviderLive do
      use Phoenix.LiveView
      use PhoenixVapor, file: Fixtures.path("components/PackageProvider.vue")
    end

    test "render when they render just their content" do
      assert PackageProviderLive.render(%{name: "Ada"}) |> html() == "<p>Hello Ada</p>"
    end

    test "with markup and behavior of their own are a compile error" do
      error =
        assert_raise CompileError, fn ->
          defmodule PackageTabsLive do
            use Phoenix.LiveView
            use PhoenixVapor, file: Fixtures.path("components/PackageTabs.vue")
          end
        end

      assert Exception.message(error) =~
               "<TabsRoot> from \"reka-ui\" can't render on the server: it has markup and behavior of its own, which work only in hybrid mode"
    end

    test "with a prop known only when rendering are a compile error" do
      error =
        assert_raise CompileError, fn ->
          defmodule PackageComponentLive do
            use Phoenix.LiveView
            use PhoenixVapor, file: Fixtures.path("components/PackageComponent.vue")
          end
        end

      assert Exception.message(error) =~
               ~s(<DialogRoot> from "reka-ui" can't render on the server: the prop `open` is only known when rendering)
    end
  end
end
