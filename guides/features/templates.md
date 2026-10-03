# Templates

## The `~VUE` sigil

`use PhoenixVapor` imports the `~VUE` sigil, which works anywhere `~H` does: in a LiveView's `render/1` or in a function component. Like `~H`, it needs `assigns` in scope.

```elixir
def render(assigns) do
  ~VUE"""
  <div :class="status">
    <h1>{{ title }}</h1>
    <ul>
      <li v-for="item in items" :key="item.id">{{ item.name }}</li>
    </ul>
    <p v-if="show_footer">{{ footer }}</p>
  </div>
  """
end
```

The template compiles at compile time to static HTML and dynamic slots. At render time, each slot is evaluated against the assigns and re-evaluated only when an assign it reads has changed, so LiveView sends the same small diffs it does for HEEx.

### Syntax

PhoenixVapor supports these parts of [Vue's template syntax](https://vuejs.org/guide/essentials/template-syntax.html):

- [Interpolation](https://vuejs.org/guide/essentials/template-syntax.html#text-interpolation): `{{ expr }}`
- [Attributes](https://vuejs.org/guide/essentials/template-syntax.html#attribute-bindings): `:class="expr"`, `:href="expr"`, and other bound attributes
- [Events](https://vuejs.org/guide/essentials/event-handling.html): `@click="save"` becomes `phx-click="save"`; handle it with `handle_event/3`
- [Conditionals](https://vuejs.org/guide/essentials/conditional.html): `v-if`, `v-else-if`, `v-else`, and `v-show`
- [Lists](https://vuejs.org/guide/essentials/list.html): `v-for="item in items"` with `:key`
- [Forms](https://vuejs.org/guide/essentials/forms.html): `v-model="name"` binds the value and sends `name_changed` on change
- Raw HTML: [`v-html`](https://vuejs.org/api/built-in-directives.html#v-html)

### Expressions

Expressions read assigns by name; `user.name` and `items[0]` work on maps and lists. Most expressions are evaluated in Elixir: comparisons, arithmetic, `&&`, `||`, `!`, ternaries, template literals, `.length`, `join` and `includes` on lists, and `trim`, `toUpperCase`, `toLowerCase`, `includes`, `startsWith`, and `endsWith` on strings. Anything else, such as `.filter(...)` with a callback, is evaluated in QuickBEAM.

### Components

A capitalized tag renders a component from the `__components__` assign, a map from tag name to a function that takes assigns and returns rendered content:

```elixir
assign(socket, __components__: %{"Card" => &MyAppWeb.Components.card/1})
```

```vue
<Card :title="post.title" />
```

## `.vue` files

`use PhoenixVapor, file: "Dashboard.vue"` makes a `.vue` file the LiveView's template. The path is relative to the module's file. Without `ref()` in `<script setup>`, the file is server-only: `render/1` comes from the template, and the rest of the LiveView is your Elixir.

```vue
<!-- lib/my_app_web/live/Dashboard.vue -->
<template>
  <h1>{{ title }}</h1>
  <p v-for="stat in stats">{{ stat.label }}: {{ stat.value }}</p>
</template>
```

```elixir
defmodule MyAppWeb.DashboardLive do
  use MyAppWeb, :live_view
  use PhoenixVapor, file: "Dashboard.vue"

  def mount(_params, _session, socket) do
    {:ok, assign(socket, title: "Dashboard", stats: Stats.all())}
  end
end
```

A `<script lang="elixir">` block is compiled into the module, so a component can live in a single file; see [Hybrid mode](hybrid.md#single-file-components).

## Function components from `.vue` files

`PhoenixVapor.Vue.component/2` defines a function component from a [`.vue` file](https://vuejs.org/guide/scaling-up/sfc.html)'s template. A [`<style scoped>`](https://vuejs.org/api/sfc-css-features.html#scoped-css) block is compiled too: the root element gets the scope attribute, and the CSS is available from a generated function.

```elixir
defmodule MyAppWeb.Components do
  use Phoenix.Component
  require PhoenixVapor.Vue

  PhoenixVapor.Vue.component(:card, "vue/Card.vue")
end
```

```elixir
MyAppWeb.Components.__vue_css_card__()
# ".card[data-v-7a7a37b1] { ... }"
```

## Rendering at runtime

`PhoenixVapor.render/2` compiles and renders a template string at runtime, for templates that aren't known at compile time. It parses the template on every call, so prefer the sigil or a `.vue` file when you can.

```elixir
PhoenixVapor.render("<p>{{ msg }}</p>", %{msg: "Hello"})
```
