defmodule PhoenixVapor.Integration.RenderingTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  defp render_to_html(rendered) do
    dynamic = rendered.dynamic.(false)

    rendered.static
    |> Enum.with_index()
    |> Enum.map(fn {s, i} ->
      case Enum.at(dynamic, i) do
        nil -> s
        %Phoenix.LiveView.Rendered{} = r -> s <> render_to_html(r)
        %Phoenix.LiveView.Comprehension{} = c -> s <> render_comprehension(c)
        d -> s <> to_string(d)
      end
    end)
    |> IO.iodata_to_binary()
  end

  defp render_comprehension(c) do
    c.entries
    |> Enum.map(fn {_, _, f} ->
      d = f.(%{}, false)

      c.static
      |> Enum.with_index()
      |> Enum.map(fn {s, i} ->
        case Enum.at(d, i) do
          nil -> s
          %Phoenix.LiveView.Rendered{} = r -> s <> render_to_html(r)
          %Phoenix.LiveView.Comprehension{} = nested -> s <> render_comprehension(nested)
          v -> s <> to_string(v)
        end
      end)
      |> IO.iodata_to_binary()
    end)
    |> IO.iodata_to_binary()
  end

  describe "text interpolation" do
    test "simple {{ }}" do
      rendered = PhoenixVapor.render("<div>{{ msg }}</div>", %{msg: "Hello"})
      assert render_to_html(rendered) == "<div>Hello</div>"
    end

    test "multiple interpolations in one text node" do
      rendered = PhoenixVapor.render("<span>{{ first }} {{ last }}</span>", %{first: "John", last: "Doe"})
      assert render_to_html(rendered) == "<span>John Doe</span>"
    end

    test "mixed static and dynamic text" do
      rendered =
        PhoenixVapor.render(
          "<span>Hello {{ name }}, you have {{ count }} items</span>",
          %{name: "World", count: 42}
        )

      assert render_to_html(rendered) == "<span>Hello World, you have 42 items</span>"
    end

    test "sibling elements with text" do
      rendered =
        PhoenixVapor.render(
          "<div><span>{{ a }}</span><span>{{ b }}</span></div>",
          %{a: "AA", b: "BB"}
        )

      assert render_to_html(rendered) == "<div><span>AA</span><span>BB</span></div>"
    end

    test "deeply nested text" do
      rendered =
        PhoenixVapor.render(
          "<div><h1>{{ title }}</h1><p>static</p><span>{{ content }}</span></div>",
          %{title: "T", content: "C"}
        )

      assert render_to_html(rendered) == "<div><h1>T</h1><p>static</p><span>C</span></div>"
    end

    test "HTML escaping" do
      rendered = PhoenixVapor.render("<div>{{ msg }}</div>", %{msg: "<script>alert(1)</script>"})
      assert render_to_html(rendered) == "<div>&lt;script&gt;alert(1)&lt;/script&gt;</div>"
    end
  end

  describe "dynamic attributes" do
    test "single :class binding" do
      rendered = PhoenixVapor.render(~s[<div :class="cls">{{ msg }}</div>], %{cls: "active", msg: "Hi"})
      assert render_to_html(rendered) == ~s[<div class="active">Hi</div>]
    end

    test "multiple dynamic attributes" do
      rendered =
        PhoenixVapor.render(
          ~s[<div :class="cls" :id="myId">{{ msg }}</div>],
          %{cls: "a", myId: "b", msg: "Hi"}
        )

      assert render_to_html(rendered) == ~s[<div class="a" id="b">Hi</div>]
    end

    test "mixed static and dynamic attributes" do
      rendered =
        PhoenixVapor.render(
          ~s[<a href="/home" :class="lc" target="_blank">{{ label }}</a>],
          %{lc: "link", label: "Go"}
        )

      html = render_to_html(rendered)
      assert html =~ ~s[href="/home"]
      assert html =~ ~s[class="link"]
      assert html =~ ~s[target="_blank"]
      assert html =~ ">Go</a>"
    end
  end

  describe "slot document order" do
    test "keeps nested property slots aligned with their elements" do
      rendered =
        PhoenixVapor.render(
          ~s[<div :class="outer"><i :class="inner"></i></div>],
          %{outer: "OUTER", inner: "INNER"}
        )

      assert render_to_html(rendered) == ~s[<div class="OUTER"><i class="INNER"></i></div>]
    end

    test "keeps structural and text slots aligned with their positions" do
      rendered =
        PhoenixVapor.render(
          ~s[<div><section><b v-if="on">Y</b></section><span>{{ label }}</span></div>],
          %{on: true, label: "L"}
        )

      assert render_to_html(rendered) == "<div><section><b>Y</b></section><span>L</span></div>"
    end
  end

  describe "v-if" do
    test "truthy condition" do
      rendered =
        PhoenixVapor.render(
          ~s[<div><p v-if="show">Yes</p></div>],
          %{show: true}
        )

      assert render_to_html(rendered) == "<div><p>Yes</p></div>"
    end

    test "falsy condition" do
      rendered =
        PhoenixVapor.render(
          ~s[<div><p v-if="show">Yes</p></div>],
          %{show: false}
        )

      assert render_to_html(rendered) == "<div></div>"
    end

    test "with else branch - true" do
      rendered =
        PhoenixVapor.render(
          ~s[<div><p v-if="show">Yes</p><p v-else>No</p></div>],
          %{show: true}
        )

      assert render_to_html(rendered) == "<div><p>Yes</p></div>"
    end

    test "with else branch - false" do
      rendered =
        PhoenixVapor.render(
          ~s[<div><p v-if="show">Yes</p><p v-else>No</p></div>],
          %{show: false}
        )

      assert render_to_html(rendered) == "<div><p>No</p></div>"
    end

    test "with dynamic content inside" do
      rendered =
        PhoenixVapor.render(
          ~s[<div><p v-if="show">{{ msg }}</p></div>],
          %{show: true, msg: "Hello"}
        )

      assert render_to_html(rendered) == "<div><p>Hello</p></div>"
    end
  end

  describe "v-for" do
    test "simple list" do
      rendered =
        PhoenixVapor.render(
          ~s[<ul><li v-for="item in items">{{ item }}</li></ul>],
          %{items: ["a", "b", "c"]}
        )

      assert render_to_html(rendered) == "<ul><li>a</li><li>b</li><li>c</li></ul>"
    end

    test "empty list" do
      rendered =
        PhoenixVapor.render(
          ~s[<ul><li v-for="item in items">{{ item }}</li></ul>],
          %{items: []}
        )

      assert render_to_html(rendered) == "<ul></ul>"
    end

    test "object list with dot access" do
      rendered =
        PhoenixVapor.render(
          ~s[<ul><li v-for="item in items">{{ item.name }}</li></ul>],
          %{items: [%{"name" => "Alice"}, %{"name" => "Bob"}]}
        )

      assert render_to_html(rendered) == "<ul><li>Alice</li><li>Bob</li></ul>"
    end
  end

  describe "v-for with dynamic attributes" do
    test "dynamic attrs on v-for element" do
      rendered =
        PhoenixVapor.render(
          ~s[<div><a v-for="item in items" :href="item.url">{{ item.name }}</a></div>],
          %{items: [%{url: "/a", name: "A"}, %{url: "/b", name: "B"}]}
        )

      html = render_to_html(rendered)
      assert html =~ ~s[href="/a"]
      assert html =~ ~s[href="/b"]
      assert html =~ ">A</a>"
      assert html =~ ">B</a>"
    end
  end

  describe "event bindings" do
    test "@click maps to phx-click" do
      rendered =
        PhoenixVapor.render(
          ~s[<button @click="handleClick">Click</button>],
          %{}
        )

      html = render_to_html(rendered)
      assert html =~ ~s[phx-click="handleClick"]
      assert html =~ ">Click</button>"
    end

    test "@submit.prevent maps to phx-submit" do
      rendered =
        PhoenixVapor.render(
          ~s[<form @submit.prevent="onSubmit"><button>Go</button></form>],
          %{}
        )

      html = render_to_html(rendered)
      assert html =~ ~s[phx-submit="onSubmit"]
    end

    test "event with dynamic content" do
      rendered =
        PhoenixVapor.render(
          ~s[<button @click="inc">Count: {{ count }}</button>],
          %{count: 42}
        )

      html = render_to_html(rendered)
      assert html =~ ~s[phx-click="inc"]
      assert html =~ "Count: 42"
    end
  end

  describe "v-show" do
    test "visible element has empty style" do
      rendered =
        PhoenixVapor.render(
          ~s[<div v-show="visible">shown</div>],
          %{visible: true}
        )

      html = render_to_html(rendered)
      assert html =~ ~s[style=""]
      assert html =~ ">shown</div>"
    end

    test "hidden element has display: none" do
      rendered =
        PhoenixVapor.render(
          ~s[<div v-show="visible">shown</div>],
          %{visible: false}
        )

      html = render_to_html(rendered)
      assert html =~ ~s[style="display: none"]
    end
  end

  describe "v-model" do
    test "renders value and phx-change" do
      rendered =
        PhoenixVapor.render(
          ~s[<input v-model="search" />],
          %{search: "hello"}
        )

      html = render_to_html(rendered)
      assert html =~ ~s[value="hello"]
      assert html =~ ~s[phx-change="search_changed"]
    end
  end

  describe "v-else-if" do
    test "first branch matches" do
      rendered =
        PhoenixVapor.render(
          ~s[<div><span v-if="a">A</span><span v-else-if="b">B</span><span v-else>C</span></div>],
          %{a: true, b: false}
        )

      html = render_to_html(rendered)
      assert html =~ "<span>A</span>"
      refute html =~ "<span>B</span>"
      refute html =~ "<span>C</span>"
    end

    test "second branch matches" do
      rendered =
        PhoenixVapor.render(
          ~s[<div><span v-if="a">A</span><span v-else-if="b">B</span><span v-else>C</span></div>],
          %{a: false, b: true}
        )

      html = render_to_html(rendered)
      assert html =~ "<span>B</span>"
      refute html =~ "<span>A</span>"
    end

    test "else branch" do
      rendered =
        PhoenixVapor.render(
          ~s[<div><span v-if="a">A</span><span v-else-if="b">B</span><span v-else>C</span></div>],
          %{a: false, b: false}
        )

      html = render_to_html(rendered)
      assert html =~ "<span>C</span>"
      refute html =~ "<span>A</span>"
    end
  end

  describe "fragments" do
    test "multiple root elements" do
      rendered =
        PhoenixVapor.render(
          ~s[<h1>{{ title }}</h1><p>{{ body }}</p>],
          %{title: "T", body: "B"}
        )

      assert render_to_html(rendered) == "<h1>T</h1><p>B</p>"
    end
  end

  describe "complex templates" do
    test "props + text + v-for combined" do
      rendered =
        PhoenixVapor.render(
          ~s[<div :class="status"><h1>{{ title }}</h1><ul><li v-for="item in items">{{ item.name }}</li></ul></div>],
          %{status: "active", title: "Dashboard", items: [%{"name" => "Alice"}, %{"name" => "Bob"}]}
        )

      html = render_to_html(rendered)
      assert html =~ ~s[class="active"]
      assert html =~ "<h1>Dashboard</h1>"
      assert html =~ "<li>Alice</li>"
      assert html =~ "<li>Bob</li>"
    end

    test "v-if inside v-for" do
      rendered =
        PhoenixVapor.render(
          ~s[<ul><li v-for="item in items"><span v-if="item.active">{{ item.name }}</span></li></ul>],
          %{items: [%{"active" => true, "name" => "Yes"}, %{"active" => false, "name" => "No"}]}
        )

      html = render_to_html(rendered)
      assert html =~ "<span>Yes</span>"
      refute html =~ "No"
    end
  end

  describe "sigil" do
    test "~VUE sigil compiles at compile time" do
      import PhoenixVapor.Sigil

      assigns = %{msg: "Hello"}

      rendered =
        ~VUE"""
        <div>{{ msg }}</div>
        """

      assert %Phoenix.LiveView.Rendered{} = rendered
      assert render_to_html(rendered) == "<div>Hello</div>"
    end

    test "use PhoenixVapor imports sigil and component helper" do
      use PhoenixVapor

      assigns = %{msg: "Hi"}

      rendered =
        vue ~VUE"""
        <span>{{ msg }}</span>
        """

      assert %Phoenix.LiveView.Rendered{} = rendered
      assert render_to_html(rendered) == "<span>Hi</span>"
    end
  end

  describe "Vue SFC loading" do
    defmodule TestComponents do
      require PhoenixVapor.Vue
      PhoenixVapor.Vue.component(:card, "../../fixtures/Card.vue")
    end

    test "component from .vue file" do
      rendered =
        TestComponents.card(%{title: "Hello", description: "World", variant: "primary"})

      html = render_to_html(rendered)
      assert html =~ ~s[class="primary"]
      assert html =~ "<h2>Hello</h2>"
      assert html =~ "<p>World</p>"
    end
  end

  describe "keyed v-for" do
    test ":key sets has_key? and entry keys" do
      rendered =
        PhoenixVapor.render(
          ~s[<ul><li v-for="item in items" :key="item.id">{{ item.name }}</li></ul>],
          %{items: [%{id: "a", name: "Alice"}, %{id: "b", name: "Bob"}]}
        )

      dynamic = rendered.dynamic.(false)
      comp = hd(dynamic)
      assert %Phoenix.LiveView.Comprehension{} = comp
      assert comp.has_key? == true
      keys = Enum.map(comp.entries, fn {key, _, _} -> key end)
      assert keys == ["a", "b"]
    end

    test "unkeyed v-for has nil keys" do
      rendered =
        PhoenixVapor.render(
          ~s[<ul><li v-for="item in items">{{ item }}</li></ul>],
          %{items: ["x", "y"]}
        )

      dynamic = rendered.dynamic.(false)
      comp = hd(dynamic)
      assert comp.has_key? == false
      keys = Enum.map(comp.entries, fn {key, _, _} -> key end)
      assert keys == [nil, nil]
    end
  end

  describe "component composition" do
    test "renders component via __components__ map" do
      card_fn = fn props ->
        PhoenixVapor.render(
          ~s[<div class="card"><h2>{{ title }}</h2></div>],
          props
        )
      end

      assigns = %{
        msg: "Hello",
        __components__: %{"MyCard" => card_fn}
      }

      rendered =
        PhoenixVapor.render(
          ~s[<div><MyCard :title="msg" /></div>],
          assigns
        )

      html = render_to_html(rendered)
      assert html =~ ~s[class="card"]
      assert html =~ "<h2>Hello</h2>"
    end

    test "component with static props" do
      badge_fn = fn props ->
        PhoenixVapor.render(
          ~s[<span class="badge">{{ label }}</span>],
          props
        )
      end

      assigns = %{
        __components__: %{"Badge" => badge_fn}
      }

      rendered =
        PhoenixVapor.render(
          ~s[<div><Badge label="New" /></div>],
          assigns
        )

      html = render_to_html(rendered)
      assert html =~ "<span"
      assert html =~ "New"
    end

    test "unknown component renders empty" do
      rendered =
        PhoenixVapor.render(
          ~s[<div><Unknown title="x" /></div>],
          %{}
        )

      html = render_to_html(rendered)
      assert html == "<div></div>"
    end
  end

  describe "scoped CSS" do
    defmodule ScopedComponents do
      require PhoenixVapor.Vue
      PhoenixVapor.Vue.component(:scoped, "../../fixtures/Scoped.vue")
    end

    test "injects scope attribute into root element" do
      rendered = ScopedComponents.scoped(%{title: "Test"})
      html = render_to_html(rendered)
      assert html =~ "data-v-"
      assert html =~ "<h2>Test</h2>"
    end

    test "generates scoped CSS" do
      css = ScopedComponents.__vue_css_scoped__()
      assert css =~ "data-v-"
      assert css =~ ".card"
      assert css =~ "background: white"
    end
  end

  describe "static content" do
    test "purely static template" do
      rendered = PhoenixVapor.render("<div><p>Hello World</p></div>", %{})
      assert render_to_html(rendered) == "<div><p>Hello World</p></div>"
    end
  end

  describe "complex expressions" do
    test "ternary operator" do
      rendered =
        PhoenixVapor.render(
          ~s[<span>{{ ok ? "yes" : "no" }}</span>],
          %{ok: true}
        )

      assert render_to_html(rendered) == "<span>yes</span>"
    end

    test "ternary false branch" do
      rendered =
        PhoenixVapor.render(
          ~s[<span>{{ ok ? "yes" : "no" }}</span>],
          %{ok: false}
        )

      assert render_to_html(rendered) == "<span>no</span>"
    end

    test "arithmetic" do
      rendered =
        PhoenixVapor.render(
          ~s[<span>{{ count + 1 }}</span>],
          %{count: 41}
        )

      assert render_to_html(rendered) == "<span>42</span>"
    end

    test "string concatenation" do
      rendered =
        PhoenixVapor.render(
          ~s[<span>{{ first + " " + last }}</span>],
          %{first: "John", last: "Doe"}
        )

      assert render_to_html(rendered) == "<span>John Doe</span>"
    end

    test "negation" do
      rendered =
        PhoenixVapor.render(
          ~s[<div v-if="!hidden">visible</div>],
          %{hidden: false}
        )

      html = render_to_html(rendered)
      assert html =~ "visible"
    end

    test "comparison" do
      rendered =
        PhoenixVapor.render(
          ~s[<span>{{ count > 0 ? "positive" : "zero" }}</span>],
          %{count: 5}
        )

      assert render_to_html(rendered) == "<span>positive</span>"
    end

    test "array access" do
      rendered =
        PhoenixVapor.render(
          "<span>{{ items[0] }}</span>",
          %{items: ["first", "second"]}
        )

      assert render_to_html(rendered) == "<span>first</span>"
    end

    test ".length on list" do
      rendered =
        PhoenixVapor.render(
          ~s[<span>{{ items.length }}</span>],
          %{items: [1, 2, 3]}
        )

      assert render_to_html(rendered) == "<span>3</span>"
    end

    test "logical AND" do
      rendered =
        PhoenixVapor.render(
          ~s[<span>{{ a && b }}</span>],
          %{a: true, b: "yes"}
        )

      assert render_to_html(rendered) == "<span>yes</span>"
    end

    test "logical OR fallback" do
      rendered =
        PhoenixVapor.render(
          ~s[<span>{{ name || "anonymous" }}</span>],
          %{name: nil}
        )

      assert render_to_html(rendered) == "<span>anonymous</span>"
    end

    test "nullish coalescing" do
      rendered =
        PhoenixVapor.render(
          ~s[<span>{{ value ?? "default" }}</span>],
          %{value: nil}
        )

      assert render_to_html(rendered) == "<span>default</span>"
    end
  end

  describe "change tracking" do
    test "unchanged assigns return nil" do
      assigns = %{msg: "Hi", cls: "a", __changed__: %{}}

      rendered = PhoenixVapor.render(~s[<div :class="cls">{{ msg }}</div>], assigns)
      dynamic = rendered.dynamic.(true)

      assert dynamic == [nil, nil]
    end

    test "only changed assign is re-evaluated" do
      assigns = %{msg: "Hi", cls: "a", __changed__: %{msg: true}}

      rendered = PhoenixVapor.render(~s[<div :class="cls">{{ msg }}</div>], assigns)
      dynamic = rendered.dynamic.(true)

      assert Enum.at(dynamic, 0) == nil
      assert Enum.at(dynamic, 1) == "Hi"
    end

    test "full render when track_changes? is false" do
      assigns = %{msg: "Hi", cls: "a", __changed__: %{}}

      rendered = PhoenixVapor.render(~s[<div :class="cls">{{ msg }}</div>], assigns)
      dynamic = rendered.dynamic.(false)

      assert dynamic == ["a", "Hi"]
    end

    test "all dynamics evaluated when no __changed__ key" do
      assigns = %{msg: "Hi", cls: "a"}

      rendered = PhoenixVapor.render(~s[<div :class="cls">{{ msg }}</div>], assigns)

      assert rendered.dynamic.(true) == ["a", "Hi"]
      assert rendered.dynamic.(false) == ["a", "Hi"]
    end

    test "structural ops re-evaluated on relevant change" do
      assigns = %{show: true, __changed__: %{show: true}}

      rendered =
        PhoenixVapor.render(~s[<div><p v-if="show">Yes</p></div>], assigns)

      dynamic = rendered.dynamic.(true)
      assert %Phoenix.LiveView.Rendered{} = hd(dynamic)
    end

    test "structural ops skipped on irrelevant change" do
      assigns = %{show: true, other: 1, __changed__: %{other: true}}

      rendered =
        PhoenixVapor.render(~s[<div><p v-if="show">Yes</p></div>], assigns)

      dynamic = rendered.dynamic.(true)
      assert hd(dynamic) == nil
    end
  end

  describe "QuickBEAM expression fallback" do
    test "arrow function in filter" do
      rendered =
        PhoenixVapor.render(
          "<span>{{ items.filter(x => x > 3).length }}</span>",
          %{items: [1, 2, 3, 4, 5]}
        )

      assert render_to_html(rendered) == "<span>2</span>"
    end

    test "arrow function in map + join" do
      rendered =
        PhoenixVapor.render(
          "<span>{{ items.map(x => x * 2).join(\", \") }}</span>",
          %{items: [1, 2, 3]}
        )

      assert render_to_html(rendered) == "<span>2, 4, 6</span>"
    end

    test "complex chain with objects" do
      rendered =
        PhoenixVapor.render(
          "<span>{{ users.filter(u => u.active).length }}</span>",
          %{users: [%{active: true}, %{active: false}, %{active: true}]}
        )

      assert render_to_html(rendered) == "<span>2</span>"
    end

    test "simple expressions still use pure Elixir" do
      rendered =
        PhoenixVapor.render(
          ~s[<span>{{ count + 1 }}</span>],
          %{count: 41}
        )

      assert render_to_html(rendered) == "<span>42</span>"
    end
  end

  describe "Reactive macro" do
    defmodule ReactiveCounter do
      use Phoenix.LiveView
      use PhoenixVapor, file: "../../fixtures/Counter.vue", runtime: :reactive
    end

    test "generates mount with initial state" do
      {:ok, socket} =
        ReactiveCounter.mount(%{}, %{}, %Phoenix.LiveView.Socket{
          assigns: %{__changed__: %{}, flash: %{}, live_action: nil},
          private: %{assign_new: {%{}, []}}
        })

      assert socket.assigns.count == 0
      assert socket.assigns.doubled == 0
    end

    test "generates render function" do
      assigns = %{count: 5, doubled: 10}
      rendered = ReactiveCounter.render(assigns)
      assert %Phoenix.LiveView.Rendered{} = rendered
      html = render_to_html(rendered)
      assert html =~ "5"
      assert html =~ "10"
    end

    test "generates handle_event for increment" do
      {:ok, socket} =
        ReactiveCounter.mount(%{}, %{}, %Phoenix.LiveView.Socket{
          assigns: %{__changed__: %{}, flash: %{}, live_action: nil},
          private: %{assign_new: {%{}, []}}
        })

      {:noreply, socket} = ReactiveCounter.handle_event("increment", %{}, socket)
      assert socket.assigns.count == 1
      assert socket.assigns.doubled == 2
    end

    test "generates handle_event for decrement" do
      {:ok, socket} =
        ReactiveCounter.mount(%{}, %{}, %Phoenix.LiveView.Socket{
          assigns: %{__changed__: %{}, flash: %{}, live_action: nil},
          private: %{assign_new: {%{}, []}}
        })

      {:noreply, socket} = ReactiveCounter.handle_event("increment", %{}, socket)
      {:noreply, socket} = ReactiveCounter.handle_event("increment", %{}, socket)
      {:noreply, socket} = ReactiveCounter.handle_event("increment", %{}, socket)
      {:noreply, socket} = ReactiveCounter.handle_event("decrement", %{}, socket)
      assert socket.assigns.count == 2
      assert socket.assigns.doubled == 4
    end

    test "generates handle_event for reset" do
      {:ok, socket} =
        ReactiveCounter.mount(%{}, %{}, %Phoenix.LiveView.Socket{
          assigns: %{__changed__: %{}, flash: %{}, live_action: nil},
          private: %{assign_new: {%{}, []}}
        })

      {:noreply, socket} = ReactiveCounter.handle_event("increment", %{}, socket)
      {:noreply, socket} = ReactiveCounter.handle_event("increment", %{}, socket)
      {:noreply, socket} = ReactiveCounter.handle_event("reset", %{}, socket)
      assert socket.assigns.count == 0
      assert socket.assigns.doubled == 0
    end
  end

  describe "vapor metadata" do
    test "injects data-vapor and data-vapor-statics when enabled" do
      ir = Vize.vapor_split!("<div>{{ msg }}</div>")
      rendered = PhoenixVapor.Renderer.to_rendered(ir, %{msg: "hello"}, vapor_metadata: true)
      html = render_to_html(rendered)

      assert html =~ "data-vapor"
      assert html =~ "data-vapor-statics="
      assert html =~ "hello"
    end

    test "statics JSON is properly escaped" do
      ir = Vize.vapor_split!("<div>{{ msg }}</div>")
      rendered = PhoenixVapor.Renderer.to_rendered(ir, %{msg: "test"}, vapor_metadata: true)

      [first | _] = rendered.static
      assert first =~ "data-vapor-statics="

      # Extract and unescape the statics JSON
      [_, json] = Regex.run(~r/data-vapor-statics="([^"]*)"/, first)

      unescaped =
        json
        |> String.replace("&amp;", "&")
        |> String.replace("&lt;", "<")
        |> String.replace("&gt;", ">")
        |> String.replace("&quot;", "\"")

      decoded = Jason.decode!(unescaped)
      assert is_list(decoded)
      assert length(decoded) == 2
    end

    test "not injected by default" do
      ir = Vize.vapor_split!("<div>{{ msg }}</div>")
      rendered = PhoenixVapor.Renderer.to_rendered(ir, %{msg: "hello"})
      html = render_to_html(rendered)

      refute html =~ "data-vapor"
    end
  end

  describe "rendered struct shape" do
    test "produces valid %Rendered{} with correct field types" do
      rendered = PhoenixVapor.render("<div>{{ msg }}</div>", %{msg: "Hi"})

      assert %Phoenix.LiveView.Rendered{} = rendered
      assert is_list(rendered.static)
      assert is_function(rendered.dynamic, 1)
      assert is_integer(rendered.fingerprint)
    end

    test "static has N+1 elements for N dynamics" do
      rendered = PhoenixVapor.render("<div>{{ a }}</div>", %{a: "x"})
      dynamic = rendered.dynamic.(false)
      assert length(rendered.static) == length(dynamic) + 1
    end

    test "fingerprint is stable for same template" do
      r1 = PhoenixVapor.render("<div>{{ a }}</div>", %{a: "x"})
      r2 = PhoenixVapor.render("<div>{{ a }}</div>", %{a: "y"})
      assert r1.fingerprint == r2.fingerprint
    end

    test "fingerprint changes for different templates" do
      r1 = PhoenixVapor.render("<div>{{ a }}</div>", %{a: "x"})
      r2 = PhoenixVapor.render("<span>{{ a }}</span>", %{a: "x"})
      assert r1.fingerprint != r2.fingerprint
    end

    test "v-if produces nested %Rendered{}" do
      rendered =
        PhoenixVapor.render(
          ~s[<div><p v-if="show">Yes</p></div>],
          %{show: true}
        )

      [dynamic] = rendered.dynamic.(false)
      assert %Phoenix.LiveView.Rendered{} = dynamic
    end

    test "v-for produces %Comprehension{}" do
      rendered =
        PhoenixVapor.render(
          ~s[<ul><li v-for="item in items">{{ item }}</li></ul>],
          %{items: ["a"]}
        )

      [dynamic] = rendered.dynamic.(false)
      assert %Phoenix.LiveView.Comprehension{} = dynamic
    end
  end
end
