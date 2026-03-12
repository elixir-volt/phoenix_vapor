defmodule LiveVueNextTest do
  use ExUnit.Case, async: true

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
      rendered = LiveVueNext.render("<div>{{ msg }}</div>", %{msg: "Hello"})
      assert render_to_html(rendered) == "<div>Hello</div>"
    end

    test "multiple interpolations in one text node" do
      rendered = LiveVueNext.render("<span>{{ first }} {{ last }}</span>", %{first: "John", last: "Doe"})
      assert render_to_html(rendered) == "<span>John Doe</span>"
    end

    test "mixed static and dynamic text" do
      rendered =
        LiveVueNext.render(
          "<span>Hello {{ name }}, you have {{ count }} items</span>",
          %{name: "World", count: 42}
        )

      assert render_to_html(rendered) == "<span>Hello World, you have 42 items</span>"
    end

    test "sibling elements with text" do
      rendered =
        LiveVueNext.render(
          "<div><span>{{ a }}</span><span>{{ b }}</span></div>",
          %{a: "AA", b: "BB"}
        )

      assert render_to_html(rendered) == "<div><span>AA</span><span>BB</span></div>"
    end

    test "deeply nested text" do
      rendered =
        LiveVueNext.render(
          "<div><h1>{{ title }}</h1><p>static</p><span>{{ content }}</span></div>",
          %{title: "T", content: "C"}
        )

      assert render_to_html(rendered) == "<div><h1>T</h1><p>static</p><span>C</span></div>"
    end

    test "HTML escaping" do
      rendered = LiveVueNext.render("<div>{{ msg }}</div>", %{msg: "<script>alert(1)</script>"})
      assert render_to_html(rendered) == "<div>&lt;script&gt;alert(1)&lt;/script&gt;</div>"
    end
  end

  describe "dynamic attributes" do
    test "single :class binding" do
      rendered = LiveVueNext.render(~s[<div :class="cls">{{ msg }}</div>], %{cls: "active", msg: "Hi"})
      assert render_to_html(rendered) == ~s[<div class="active">Hi</div>]
    end

    test "multiple dynamic attributes" do
      rendered =
        LiveVueNext.render(
          ~s[<div :class="cls" :id="myId">{{ msg }}</div>],
          %{cls: "a", myId: "b", msg: "Hi"}
        )

      assert render_to_html(rendered) == ~s[<div class="a" id="b">Hi</div>]
    end

    test "mixed static and dynamic attributes" do
      rendered =
        LiveVueNext.render(
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

  describe "v-if" do
    test "truthy condition" do
      rendered =
        LiveVueNext.render(
          ~s[<div><p v-if="show">Yes</p></div>],
          %{show: true}
        )

      assert render_to_html(rendered) == "<div><p>Yes</p></div>"
    end

    test "falsy condition" do
      rendered =
        LiveVueNext.render(
          ~s[<div><p v-if="show">Yes</p></div>],
          %{show: false}
        )

      assert render_to_html(rendered) == "<div></div>"
    end

    test "with else branch - true" do
      rendered =
        LiveVueNext.render(
          ~s[<div><p v-if="show">Yes</p><p v-else>No</p></div>],
          %{show: true}
        )

      assert render_to_html(rendered) == "<div><p>Yes</p></div>"
    end

    test "with else branch - false" do
      rendered =
        LiveVueNext.render(
          ~s[<div><p v-if="show">Yes</p><p v-else>No</p></div>],
          %{show: false}
        )

      assert render_to_html(rendered) == "<div><p>No</p></div>"
    end

    test "with dynamic content inside" do
      rendered =
        LiveVueNext.render(
          ~s[<div><p v-if="show">{{ msg }}</p></div>],
          %{show: true, msg: "Hello"}
        )

      assert render_to_html(rendered) == "<div><p>Hello</p></div>"
    end
  end

  describe "v-for" do
    test "simple list" do
      rendered =
        LiveVueNext.render(
          ~s[<ul><li v-for="item in items">{{ item }}</li></ul>],
          %{items: ["a", "b", "c"]}
        )

      assert render_to_html(rendered) == "<ul><li>a</li><li>b</li><li>c</li></ul>"
    end

    test "empty list" do
      rendered =
        LiveVueNext.render(
          ~s[<ul><li v-for="item in items">{{ item }}</li></ul>],
          %{items: []}
        )

      assert render_to_html(rendered) == "<ul></ul>"
    end

    test "object list with dot access" do
      rendered =
        LiveVueNext.render(
          ~s[<ul><li v-for="item in items">{{ item.name }}</li></ul>],
          %{items: [%{"name" => "Alice"}, %{"name" => "Bob"}]}
        )

      assert render_to_html(rendered) == "<ul><li>Alice</li><li>Bob</li></ul>"
    end
  end

  describe "v-for with dynamic attributes" do
    test "dynamic attrs on v-for element" do
      rendered =
        LiveVueNext.render(
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
        LiveVueNext.render(
          ~s[<button @click="handleClick">Click</button>],
          %{}
        )

      html = render_to_html(rendered)
      assert html =~ ~s[phx-click="handleClick"]
      assert html =~ ">Click</button>"
    end

    test "@submit.prevent maps to phx-submit" do
      rendered =
        LiveVueNext.render(
          ~s[<form @submit.prevent="onSubmit"><button>Go</button></form>],
          %{}
        )

      html = render_to_html(rendered)
      assert html =~ ~s[phx-submit="onSubmit"]
    end

    test "event with dynamic content" do
      rendered =
        LiveVueNext.render(
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
        LiveVueNext.render(
          ~s[<div v-show="visible">shown</div>],
          %{visible: true}
        )

      html = render_to_html(rendered)
      assert html =~ ~s[style=""]
      assert html =~ ">shown</div>"
    end

    test "hidden element has display: none" do
      rendered =
        LiveVueNext.render(
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
        LiveVueNext.render(
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
        LiveVueNext.render(
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
        LiveVueNext.render(
          ~s[<div><span v-if="a">A</span><span v-else-if="b">B</span><span v-else>C</span></div>],
          %{a: false, b: true}
        )

      html = render_to_html(rendered)
      assert html =~ "<span>B</span>"
      refute html =~ "<span>A</span>"
    end

    test "else branch" do
      rendered =
        LiveVueNext.render(
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
        LiveVueNext.render(
          ~s[<h1>{{ title }}</h1><p>{{ body }}</p>],
          %{title: "T", body: "B"}
        )

      assert render_to_html(rendered) == "<h1>T</h1><p>B</p>"
    end
  end

  describe "complex templates" do
    test "props + text + v-for combined" do
      rendered =
        LiveVueNext.render(
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
        LiveVueNext.render(
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
      import LiveVueNext.Sigil

      assigns = %{msg: "Hello"}

      rendered =
        ~VUE"""
        <div>{{ msg }}</div>
        """

      assert %Phoenix.LiveView.Rendered{} = rendered
      assert render_to_html(rendered) == "<div>Hello</div>"
    end

    test "use LiveVueNext imports sigil and component helper" do
      use LiveVueNext

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
      require LiveVueNext.Vue
      LiveVueNext.Vue.component(:card, "fixtures/Card.vue")
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
        LiveVueNext.render(
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
        LiveVueNext.render(
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
        LiveVueNext.render(
          ~s[<div class="card"><h2>{{ title }}</h2></div>],
          props
        )
      end

      assigns = %{
        msg: "Hello",
        __components__: %{"MyCard" => card_fn}
      }

      rendered =
        LiveVueNext.render(
          ~s[<div><MyCard :title="msg" /></div>],
          assigns
        )

      html = render_to_html(rendered)
      assert html =~ ~s[class="card"]
      assert html =~ "<h2>Hello</h2>"
    end

    test "component with static props" do
      badge_fn = fn props ->
        LiveVueNext.render(
          ~s[<span class="badge">{{ label }}</span>],
          props
        )
      end

      assigns = %{
        __components__: %{"Badge" => badge_fn}
      }

      rendered =
        LiveVueNext.render(
          ~s[<div><Badge label="New" /></div>],
          assigns
        )

      html = render_to_html(rendered)
      assert html =~ "<span"
      assert html =~ "New"
    end

    test "unknown component renders empty" do
      rendered =
        LiveVueNext.render(
          ~s[<div><Unknown title="x" /></div>],
          %{}
        )

      html = render_to_html(rendered)
      assert html == "<div></div>"
    end
  end

  describe "scoped CSS" do
    defmodule ScopedComponents do
      require LiveVueNext.Vue
      LiveVueNext.Vue.component(:scoped, "fixtures/Scoped.vue")
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
      rendered = LiveVueNext.render("<div><p>Hello World</p></div>", %{})
      assert render_to_html(rendered) == "<div><p>Hello World</p></div>"
    end
  end

  describe "complex expressions" do
    test "ternary operator" do
      rendered =
        LiveVueNext.render(
          ~s[<span>{{ ok ? "yes" : "no" }}</span>],
          %{ok: true}
        )

      assert render_to_html(rendered) == "<span>yes</span>"
    end

    test "ternary false branch" do
      rendered =
        LiveVueNext.render(
          ~s[<span>{{ ok ? "yes" : "no" }}</span>],
          %{ok: false}
        )

      assert render_to_html(rendered) == "<span>no</span>"
    end

    test "arithmetic" do
      rendered =
        LiveVueNext.render(
          ~s[<span>{{ count + 1 }}</span>],
          %{count: 41}
        )

      assert render_to_html(rendered) == "<span>42</span>"
    end

    test "string concatenation" do
      rendered =
        LiveVueNext.render(
          ~s[<span>{{ first + " " + last }}</span>],
          %{first: "John", last: "Doe"}
        )

      assert render_to_html(rendered) == "<span>John Doe</span>"
    end

    test "negation" do
      rendered =
        LiveVueNext.render(
          ~s[<div v-if="!hidden">visible</div>],
          %{hidden: false}
        )

      html = render_to_html(rendered)
      assert html =~ "visible"
    end

    test "comparison" do
      rendered =
        LiveVueNext.render(
          ~s[<span>{{ count > 0 ? "positive" : "zero" }}</span>],
          %{count: 5}
        )

      assert render_to_html(rendered) == "<span>positive</span>"
    end

    test "array access" do
      rendered =
        LiveVueNext.render(
          "<span>{{ items[0] }}</span>",
          %{items: ["first", "second"]}
        )

      assert render_to_html(rendered) == "<span>first</span>"
    end

    test ".length on list" do
      rendered =
        LiveVueNext.render(
          ~s[<span>{{ items.length }}</span>],
          %{items: [1, 2, 3]}
        )

      assert render_to_html(rendered) == "<span>3</span>"
    end

    test "logical AND" do
      rendered =
        LiveVueNext.render(
          ~s[<span>{{ a && b }}</span>],
          %{a: true, b: "yes"}
        )

      assert render_to_html(rendered) == "<span>yes</span>"
    end

    test "logical OR fallback" do
      rendered =
        LiveVueNext.render(
          ~s[<span>{{ name || "anonymous" }}</span>],
          %{name: nil}
        )

      assert render_to_html(rendered) == "<span>anonymous</span>"
    end

    test "nullish coalescing" do
      rendered =
        LiveVueNext.render(
          ~s[<span>{{ value ?? "default" }}</span>],
          %{value: nil}
        )

      assert render_to_html(rendered) == "<span>default</span>"
    end
  end

  describe "change tracking" do
    test "unchanged assigns return nil" do
      assigns = %{msg: "Hi", cls: "a", __changed__: %{}}

      rendered = LiveVueNext.render(~s[<div :class="cls">{{ msg }}</div>], assigns)
      dynamic = rendered.dynamic.(true)

      assert dynamic == [nil, nil]
    end

    test "only changed assign is re-evaluated" do
      assigns = %{msg: "Hi", cls: "a", __changed__: %{msg: true}}

      rendered = LiveVueNext.render(~s[<div :class="cls">{{ msg }}</div>], assigns)
      dynamic = rendered.dynamic.(true)

      assert Enum.at(dynamic, 0) == nil
      assert Enum.at(dynamic, 1) == "Hi"
    end

    test "full render when track_changes? is false" do
      assigns = %{msg: "Hi", cls: "a", __changed__: %{}}

      rendered = LiveVueNext.render(~s[<div :class="cls">{{ msg }}</div>], assigns)
      dynamic = rendered.dynamic.(false)

      assert dynamic == ["a", "Hi"]
    end

    test "all dynamics evaluated when no __changed__ key" do
      assigns = %{msg: "Hi", cls: "a"}

      rendered = LiveVueNext.render(~s[<div :class="cls">{{ msg }}</div>], assigns)

      assert rendered.dynamic.(true) == ["a", "Hi"]
      assert rendered.dynamic.(false) == ["a", "Hi"]
    end

    test "structural ops re-evaluated on relevant change" do
      assigns = %{show: true, __changed__: %{show: true}}

      rendered =
        LiveVueNext.render(~s[<div><p v-if="show">Yes</p></div>], assigns)

      dynamic = rendered.dynamic.(true)
      assert %Phoenix.LiveView.Rendered{} = hd(dynamic)
    end

    test "structural ops skipped on irrelevant change" do
      assigns = %{show: true, other: 1, __changed__: %{other: true}}

      rendered =
        LiveVueNext.render(~s[<div><p v-if="show">Yes</p></div>], assigns)

      dynamic = rendered.dynamic.(true)
      assert hd(dynamic) == nil
    end
  end

  describe "expression evaluation" do
    test "simple identifier" do
      assert LiveVueNext.Expr.eval("msg", %{msg: "hello"}) == "hello"
    end

    test "dot access" do
      assert LiveVueNext.Expr.eval("user.name", %{user: %{name: "Dan"}}) == "Dan"
    end

    test "deep dot access" do
      assigns = %{user: %{address: %{city: "Moscow"}}}
      assert LiveVueNext.Expr.eval("user.address.city", assigns) == "Moscow"
    end

    test "atom and string keys" do
      assert LiveVueNext.Expr.eval("x", %{x: 1}) == 1
      assert LiveVueNext.Expr.eval("x", %{"x" => 2}) == 2
    end

    test "missing key returns nil" do
      assert LiveVueNext.Expr.eval("missing", %{}) == nil
    end

    test "static expression passthrough" do
      assert LiveVueNext.Expr.eval({:static_, "hello"}, %{}) == "hello"
    end

    test "boolean literals" do
      assert LiveVueNext.Expr.eval("true", %{}) == true
      assert LiveVueNext.Expr.eval("false", %{}) == false
    end

    test "null literal" do
      assert LiveVueNext.Expr.eval("null", %{}) == nil
    end

    test "ternary expression" do
      assert LiveVueNext.Expr.eval(~s[ok ? "y" : "n"], %{ok: true}) == "y"
      assert LiveVueNext.Expr.eval(~s[ok ? "y" : "n"], %{ok: false}) == "n"
    end

    test "arithmetic expressions" do
      assert LiveVueNext.Expr.eval("a + b", %{a: 2, b: 3}) == 5
      assert LiveVueNext.Expr.eval("a - b", %{a: 10, b: 3}) == 7
      assert LiveVueNext.Expr.eval("a * b", %{a: 4, b: 5}) == 20
    end

    test "comparison expressions" do
      assert LiveVueNext.Expr.eval("a > b", %{a: 5, b: 3}) == true
      assert LiveVueNext.Expr.eval("a === b", %{a: 1, b: 1}) == true
      assert LiveVueNext.Expr.eval("a !== b", %{a: 1, b: 2}) == true
    end

    test "logical expressions" do
      assert LiveVueNext.Expr.eval("a && b", %{a: true, b: "yes"}) == "yes"
      assert LiveVueNext.Expr.eval("a && b", %{a: false, b: "yes"}) == false
      assert LiveVueNext.Expr.eval("a || b", %{a: nil, b: "fallback"}) == "fallback"
      assert LiveVueNext.Expr.eval("a ?? b", %{a: nil, b: "default"}) == "default"
      assert LiveVueNext.Expr.eval("a ?? b", %{a: 0, b: "default"}) == 0
    end

    test "unary expressions" do
      assert LiveVueNext.Expr.eval("!x", %{x: false}) == true
      assert LiveVueNext.Expr.eval("-x", %{x: 5}) == -5
    end

    test "member expression computed" do
      assert LiveVueNext.Expr.eval("items.length", %{items: [1, 2, 3]}) == 3
    end

    test "array access expression" do
      assigns = %{items: ["a", "b", "c"]}
      assert LiveVueNext.Expr.eval("items[1]", assigns) == "b"
    end

    test "typeof" do
      assert LiveVueNext.Expr.eval("typeof x", %{x: 42}) == "number"
      assert LiveVueNext.Expr.eval("typeof x", %{x: "hi"}) == "string"
      assert LiveVueNext.Expr.eval("typeof x", %{x: nil}) == "undefined"
    end

    test "eval_values concatenates" do
      values = [{:static_, "Hello "}, "name", {:static_, "!"}]
      assert LiveVueNext.Expr.eval_values(values, %{name: "World"}) == "Hello World!"
    end

    test "assign_keys extracts identifiers" do
      assert LiveVueNext.Expr.assign_keys("msg") == [:msg]
      assert :user in LiveVueNext.Expr.assign_keys("user.name")
      assert LiveVueNext.Expr.assign_keys({:static_, "text"}) == []
    end

    test "assign_keys for complex expressions" do
      keys = LiveVueNext.Expr.assign_keys("a > b ? x : y")
      assert :a in keys
      assert :b in keys
      assert :x in keys
      assert :y in keys
    end

    test "string methods" do
      assert LiveVueNext.Expr.eval(~s[s.trim()], %{s: "  hi  "}) == "hi"
      assert LiveVueNext.Expr.eval(~s[s.toUpperCase()], %{s: "hi"}) == "HI"
      assert LiveVueNext.Expr.eval(~s[s.toLowerCase()], %{s: "HI"}) == "hi"
    end

    test "array methods" do
      assigns = %{items: ["a", "b", "c"]}
      assert LiveVueNext.Expr.eval(~s[items.includes("b")], assigns) == true
      assert LiveVueNext.Expr.eval(~s[items.includes("z")], assigns) == false
    end
  end

  describe "QuickBEAM expression fallback" do
    test "arrow function in filter" do
      rendered =
        LiveVueNext.render(
          "<span>{{ items.filter(x => x > 3).length }}</span>",
          %{items: [1, 2, 3, 4, 5]}
        )

      assert render_to_html(rendered) == "<span>2</span>"
    end

    test "arrow function in map + join" do
      rendered =
        LiveVueNext.render(
          "<span>{{ items.map(x => x * 2).join(\", \") }}</span>",
          %{items: [1, 2, 3]}
        )

      assert render_to_html(rendered) == "<span>2, 4, 6</span>"
    end

    test "complex chain with objects" do
      rendered =
        LiveVueNext.render(
          "<span>{{ users.filter(u => u.active).length }}</span>",
          %{users: [%{active: true}, %{active: false}, %{active: true}]}
        )

      assert render_to_html(rendered) == "<span>2</span>"
    end

    test "simple expressions still use pure Elixir" do
      rendered =
        LiveVueNext.render(
          ~s[<span>{{ count + 1 }}</span>],
          %{count: 41}
        )

      assert render_to_html(rendered) == "<span>42</span>"
    end
  end

  describe "script setup parsing" do
    test "extracts refs with initial values" do
      {refs, _, _, _} =
        LiveVueNext.ScriptSetup.parse("""
        import { ref } from "vue"
        const count = ref(0)
        const name = ref("hello")
        """)

      assert refs == %{"count" => "0", "name" => "\"hello\""}
    end

    test "extracts computed expressions" do
      {_, computeds, _, _} =
        LiveVueNext.ScriptSetup.parse("""
        import { ref, computed } from "vue"
        const count = ref(0)
        const doubled = computed(() => count.value * 2)
        """)

      assert computeds["doubled"] == "count.value * 2"
    end

    test "extracts function names" do
      {_, _, functions, _} =
        LiveVueNext.ScriptSetup.parse("""
        function increment() { count.value++ }
        function reset() { count.value = 0 }
        """)

      assert "increment" in functions
      assert "reset" in functions
    end

    test "extracts defineProps" do
      {_, _, _, props} =
        LiveVueNext.ScriptSetup.parse("""
        defineProps(["title", "count"])
        """)

      assert props == ["title", "count"]
    end

    test "evaluates initial state via QuickBEAM" do
      refs = %{"count" => "0", "items" => "[]", "name" => "\"world\""}
      state = LiveVueNext.ScriptSetup.eval_initial_state(refs)

      assert state.count == 0
      assert state.items == []
      assert state.name == "world"
    end
  end

  describe "rendered struct shape" do
    test "produces valid %Rendered{} with correct field types" do
      rendered = LiveVueNext.render("<div>{{ msg }}</div>", %{msg: "Hi"})

      assert %Phoenix.LiveView.Rendered{} = rendered
      assert is_list(rendered.static)
      assert is_function(rendered.dynamic, 1)
      assert is_integer(rendered.fingerprint)
    end

    test "static has N+1 elements for N dynamics" do
      rendered = LiveVueNext.render("<div>{{ a }}</div>", %{a: "x"})
      dynamic = rendered.dynamic.(false)
      assert length(rendered.static) == length(dynamic) + 1
    end

    test "fingerprint is stable for same template" do
      r1 = LiveVueNext.render("<div>{{ a }}</div>", %{a: "x"})
      r2 = LiveVueNext.render("<div>{{ a }}</div>", %{a: "y"})
      assert r1.fingerprint == r2.fingerprint
    end

    test "fingerprint changes for different templates" do
      r1 = LiveVueNext.render("<div>{{ a }}</div>", %{a: "x"})
      r2 = LiveVueNext.render("<span>{{ a }}</span>", %{a: "x"})
      assert r1.fingerprint != r2.fingerprint
    end

    test "v-if produces nested %Rendered{}" do
      rendered =
        LiveVueNext.render(
          ~s[<div><p v-if="show">Yes</p></div>],
          %{show: true}
        )

      [dynamic] = rendered.dynamic.(false)
      assert %Phoenix.LiveView.Rendered{} = dynamic
    end

    test "v-for produces %Comprehension{}" do
      rendered =
        LiveVueNext.render(
          ~s[<ul><li v-for="item in items">{{ item }}</li></ul>],
          %{items: ["a"]}
        )

      [dynamic] = rendered.dynamic.(false)
      assert %Phoenix.LiveView.Comprehension{} = dynamic
    end
  end
end
