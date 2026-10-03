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

  describe "hybrid props" do
    test "every defineProps form declares props" do
      for script <- [
            ~s|defineProps(["users", "title"])|,
            ~s|const props = defineProps({ users: Array, title: { type: String } })|,
            ~s|const props = defineProps<{ users: string[]; title?: string }>()|
          ] do
        assert {_, _, _, _, ["users", "title"]} = PhoenixVapor.ScriptSetup.parse(script)
      end
    end

    test "props the template reads go to the client; props only server actions read don't" do
      classification =
        Classifier.classify(
          %{"q" => ~s("")},
          %{},
          ["save"],
          %{"save" => ~s|"use server"; audit(secret)|},
          ["title", "secret"],
          ["title", "q"]
        )

      assert classification.client_props == ["title"]
      assert classification.server_only_props == ["secret"]
    end
  end

  test "compiled splits render the same HTML as source splits" do
    template = """
    <ul :class="cls">
      <li v-for="item in items" :key="item.id">{{ item.name.toUpperCase() }} {{ item.qty > 1 ? "many" : "one" }}</li>
      <li v-if="items.length === 0">none</li>
      <li v-else>{{ items.filter(i => i.qty > 1).length }} with many</li>
    </ul>
    """

    assigns = %{cls: "list", items: [%{id: 1, name: "a", qty: 2}, %{id: 2, name: "b", qty: 1}]}
    split = Vize.vapor_split!(template)

    html =
      &(&1
        |> PhoenixVapor.Renderer.to_rendered(assigns)
        |> Phoenix.HTML.Safe.to_iodata()
        |> IO.iodata_to_binary())

    assert html.(PhoenixVapor.Renderer.compile(split)) == html.(split)
    assert html.(split) =~ "A many"
    assert html.(split) =~ "1 with many"
  end

  test "methods Elixir doesn't evaluate fall back to JavaScript" do
    render = fn template, assigns ->
      template
      |> PhoenixVapor.render(assigns)
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()
    end

    assert render.("<p>{{ name.padStart(5, '*') }}</p>", %{name: "ab"}) == "<p>***ab</p>"

    assert render.("<p>{{ items.filter(i => i > 1).length }}</p>", %{items: [1, 2, 3]}) ==
             "<p>2</p>"
  end

  describe "event bindings" do
    defp html(template, assigns) do
      template
      |> PhoenixVapor.render(assigns)
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()
    end

    test "LiveView templates get phx-* attributes, with handlers escaped" do
      assert html(~S|<button @click='say("hi")'>x</button>|, %{}) ==
               ~s|<button phx-click="say(&quot;hi&quot;)">x</button>|
    end

    test "v-model gets phx-change after its value" do
      assert html(~S|<input v-model="name">|, %{name: "Ann"}) ==
               ~s(<input value="Ann" phx-change="name_changed">)
    end

    test "events inside v-for keep their attribute" do
      assert html(~S|<ul><li v-for="i in items" @click="pick">{{ i }}</li></ul>|, %{items: [1]}) ==
               ~s(<ul><li phx-click="pick">1</li></ul>)
    end

    test "hybrid server HTML leaves events to the client" do
      split =
        ~S|<button @click="pick(c)">{{ label }}</button>|
        |> Vize.vapor_split!()
        |> PhoenixVapor.Renderer.compile(events: false)

      refute Enum.join(split.statics) =~ "phx-"
    end
  end

  test "rendering a runtime template creates no atoms" do
    names = for i <- 1..4, do: "pv_unseen_#{System.unique_integer([:positive])}_#{i}"
    [a, b, c, d] = names

    template = """
    <p :class="#{a}">{{ #{b}.x }}</p>
    <li v-for="#{c} in items">{{ #{c} }}</li>
    <MyCard :#{d}="1" />
    """

    PhoenixVapor.render(template, %{items: [1], __components__: %{}})
    |> Phoenix.HTML.Safe.to_iodata()

    for name <- names do
      assert_raise ArgumentError, fn -> String.to_existing_atom(name) end
    end
  end

  test "change tracking still skips slots whose assigns didn't change" do
    split =
      "<p>{{ a }}</p><b>{{ b }}</b>" |> Vize.vapor_split!() |> PhoenixVapor.Renderer.compile()

    rendered = PhoenixVapor.Renderer.to_rendered(split, %{a: 1, b: 2, __changed__: %{b: true}})

    assert [nil, "2"] = rendered.dynamic.(true)
  end
end
