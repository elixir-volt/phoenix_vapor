defmodule PhoenixVapor.RegressionsTest do
  use ExUnit.Case, async: true

  alias PhoenixVapor.Fixtures

  alias PhoenixVapor.Hybrid.{Classifier, ClientCodegen}

  describe "attributes injected into the root tag" do
    defmodule Scoped do
      require PhoenixVapor.Vue
      PhoenixVapor.Vue.component(:card, Fixtures.path("ScopedTitle.vue"))
    end

    test "the scope attribute matches the CSS and survives > in attribute values" do
      html =
        %{title: "Hi"}
        |> Scoped.card()
        |> Phoenix.HTML.Safe.to_iodata()
        |> IO.iodata_to_binary()

      [scope] = Regex.run(~r/data-v-[0-9a-f]{8}/, Scoped.__vue_css_card__())

      assert html =~ ~s(<div #{scope} title="a &gt; b" class="card">Hi</div>)
    end

    test "vapor metadata goes after the tag name" do
      split = Vize.split_template!(~s(<div title="a > b"><p>{{ x }}</p></div>))
      [first | _] = PhoenixVapor.Renderer.to_rendered(split, %{x: 1}, vapor_metadata: true).static

      assert first =~
               ~r/\A<div data-vapor data-vapor-statics="[^"]*" data-vapor-keys="[^"]*" title="a &gt; b">/
    end
  end

  test "the client module leaves out a <script lang=\"elixir\"> after <script setup>" do
    sfc = File.read!(Fixtures.path("ElixirAfterSetup.vue"))
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
            use PhoenixVapor, file: Fixtures.path("Counter.vue"), runtime: :ful
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
    split = Vize.split_template!(template)

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

    test "v-model gets phx-change and its value" do
      assert html(~S|<input v-model="name">|, %{name: "Ann"}) ==
               ~s(<input phx-change="name_changed" value="Ann">)
    end

    test "events inside v-for keep their attribute" do
      assert html(~S|<ul><li v-for="i in items" @click="pick">{{ i }}</li></ul>|, %{items: [1]}) ==
               ~s(<ul><li phx-click="pick">1</li></ul>)
    end

    test "hybrid server HTML leaves events to the client" do
      split =
        ~S|<button @click="pick(c)">{{ label }}</button>|
        |> Vize.split_template!()
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
      "<p>{{ a }}</p><b>{{ b }}</b>" |> Vize.split_template!() |> PhoenixVapor.Renderer.compile()

    rendered = PhoenixVapor.Renderer.to_rendered(split, %{a: 1, b: 2, __changed__: %{b: true}})

    assert [nil, "2"] = rendered.dynamic.(true)
  end

  test "an interpolation after a text node in a nested list renders" do
    html =
      ~S|<ul><li>a<ul><li>{{ b }}</li></ul></li></ul>|
      |> PhoenixVapor.render(%{b: "B"})
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()

    assert html == "<ul><li>a<ul><li>B</li></ul></li></ul>"
  end

  describe "Vue rendering semantics" do
    defp render_html(template, assigns) do
      template
      |> PhoenixVapor.render(assigns)
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()
    end

    test "object class bindings" do
      assert render_html(~S|<p class="a" :class="{ on: active, off: !active }">x</p>|, %{
               active: true
             }) ==
               ~s(<p class="a on">x</p>)
    end

    test "false boolean attributes are left out" do
      assert render_html(~S|<button :disabled="busy">x</button>|, %{busy: false}) ==
               "<button>x</button>"

      assert render_html(~S|<button :disabled="busy">x</button>|, %{busy: true}) ==
               "<button disabled>x</button>"
    end

    test "v-for binds the index, and a map's key" do
      assert render_html(~S|<i v-for="(item, i) in items">{{ i }}{{ item }}</i>|, %{
               items: ["a", "b"]
             }) ==
               "<i>0a</i><i>1b</i>"

      assert render_html(~S|<i v-for="(value, key) in map">{{ key }}={{ value }}</i>|, %{
               map: %{"x" => 1}
             }) ==
               "<i>x=1</i>"
    end

    test "objects and lists display as JSON, and null as nothing" do
      assert render_html(~S"<p>{{ list }}|{{ none }}</p>", %{list: [1], none: nil}) ==
               "<p>[\n  1\n]|</p>"
    end

    test "a root v-if renders once" do
      assert render_html(~S|<p v-if="ok">yes</p><p v-else>no</p>|, %{ok: true}) == "<p>yes</p>"
    end
  end
end
