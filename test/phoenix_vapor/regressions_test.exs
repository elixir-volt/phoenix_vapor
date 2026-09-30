defmodule PhoenixVapor.RegressionsTest do
  use ExUnit.Case, async: true

  alias PhoenixVapor.Hybrid.{Classifier, ClientCodegen}

  describe "attributes injected into the root tag" do
    defmodule Scoped do
      require PhoenixVapor.Vue
      PhoenixVapor.Vue.component(:card, "../fixtures/ScopedTitle.vue")
    end

    test "the scope attribute matches the CSS and survives > in attribute values" do
      html =
        %{title: "Hi"}
        |> Scoped.card()
        |> Phoenix.HTML.Safe.to_iodata()
        |> IO.iodata_to_binary()

      [scope] = Regex.run(~r/data-v-[0-9a-f]{8}/, Scoped.__vue_css_card__())

      assert html =~ ~s(<div #{scope} title="a > b" class="card">Hi</div>)
    end

    test "vapor metadata goes after the tag name" do
      split = Vize.vapor_split!(~s(<div title="a > b"><p>{{ x }}</p></div>))
      [first | _] = PhoenixVapor.Renderer.to_rendered(split, %{x: 1}, vapor_metadata: true).static

      assert first =~ ~r/\A<div data-vapor data-vapor-statics="[^"]*" title="a > b">/
    end
  end

  test "the client module leaves out a <script lang=\"elixir\"> after <script setup>" do
    sfc = File.read!("test/fixtures/ElixirAfterSetup.vue")
    %{script_setup: %{content: script}} = Vize.parse_sfc!(sfc)
    {refs, computeds, functions, bodies, props} = PhoenixVapor.ScriptSetup.parse(script)

    {:ok, js} =
      ClientCodegen.generate(sfc, Classifier.classify(refs, computeds, functions, bodies, props))

    refute js =~ "def mount"
    assert js =~ "const count = ref(0)"
  end

  test "an unknown :runtime is a compile error" do
    assert_raise ArgumentError, ~r/unknown :runtime :ful/, fn ->
      Code.compile_quoted(
        quote do
          defmodule PhoenixVapor.RegressionsTest.Typo do
            use PhoenixVapor, file: "test/fixtures/Counter.vue", runtime: :ful
          end
        end
      )
    end
  end

  test "LiveVue.unwrap!/1 raises the JavaScript error itself" do
    error = %QuickBEAM.JSError{message: "boom", name: "TypeError"}
    assert_raise QuickBEAM.JSError, fn -> PhoenixVapor.LiveVue.unwrap!({:error, error}) end
    assert PhoenixVapor.LiveVue.unwrap!({:ok, "<p></p>"}) == "<p></p>"
  end
end
