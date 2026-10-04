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

Expressions read assigns by name; `user.name` and `items[0]` work on maps and lists. Most expressions are evaluated in Elixir: comparisons, arithmetic, `&&`, `||`, `!`, ternaries, template literals, `.length`, `join` and `includes` on lists, and `trim`, `toUpperCase`, `toLowerCase`, `includes`, `startsWith`, and `endsWith` on strings. Anything else, such as `.filter(...)` with a callback, is evaluated in QuickBEAM, with the [globals Vue allows](https://vuejs.org/guide/essentials/template-syntax.html#restricted-globals-access) such as `Math` and `JSON`. A name that isn't an assign is `null`, as Vue treats an unknown name; an expression that fails, such as a call to something that isn't a function, raises `PhoenixVapor.ExpressionError` with its file, line, and column.

Values display as in Vue: `null` as nothing, and objects and lists as JSON. Attributes follow [Vue's server renderer](https://vuejs.org/guide/scaling-up/ssr.html): `null` and a false boolean attribute such as `disabled` leave the attribute out, and `class` and `style` take objects and arrays.

### Components

In a `.vue` file, a component imported from another `.vue` file renders on the server: its template is compiled with the parent's, its [props](https://vuejs.org/guide/components/props.html) become its assigns, [slot](https://vuejs.org/guide/components/slots.html) content renders with the parent's assigns, and other attributes [fall through](https://vuejs.org/guide/components/attrs.html) to its root element, with `class` and `style` merged. Imports resolve as in the browser build, relative to the file or through [Volt aliases](https://hexdocs.pm/volt/features.html) such as `@/`.

```vue
<script setup>
import Card from "@/ui/Card.vue"
</script>

<template>
  <Card :title="post.title" class="mt-4">
    <p>{{ post.body }}</p>
  </Card>
</template>
```

### Components from packages

A component from a package, such as a [Reka UI](https://reka-ui.com) primitive, gets its markup from its JavaScript. In a hybrid component, when everything it receives is known at compile time, Vue's [server renderer](https://vuejs.org/guide/scaling-up/ssr.html) runs it once in QuickBEAM while the template compiles, and its HTML becomes part of the template. Rendering then runs no JavaScript.

```vue
<script setup>
import { ref } from "vue"
import { TooltipProvider, TabsRoot, TabsList, TabsTrigger, TabsContent } from "reka-ui"

const tab = ref("general")
</script>

<template>
  <TooltipProvider>
    <TabsRoot v-model="tab">
      <TabsList>
        <TabsTrigger value="general">General</TabsTrigger>
      </TabsList>
      <TabsContent value="general"><p>{{ project.name }}</p></TabsContent>
    </TabsRoot>
  </TooltipProvider>
</template>
```

`TooltipProvider` renders only its content, and the Tabs render with Reka's markup and ARIA attributes. Package components inside one another render together, so parts such as `TabsList` get their parent's context. The template's own content inside them, such as `{{ project.name }}`, stays dynamic. So does a `v-for` or `v-if` of the template's own: a package part inside it, such as a `TooltipRoot` per row, renders once in its ancestors' context, and the loop repeats that markup.

This is for [hybrid mode](hybrid.md), where the server renders the first paint and Vue takes over in the browser. Known values are static props, literals, [macro](#macros) results, the initial values of refs, which the browser renders first too, and expressions of those, such as `:open="selected !== null"` while `selected` starts as `null`.

In other modes nothing takes over in the browser, so frozen markup from a component with behavior, such as tabs whose triggers never switch, would look interactive and do nothing. There, a package component renders only when it renders just its content, as a provider such as `TooltipProvider` does, and any other is a compile error.

A package component that receives a value known only when rendering, such as `:open="row.open"` inside a `v-for`, or that passes props to its slot content, can't render on the server. In hybrid mode it's left out of the first render, with a compile-time warning that says why, and appears when the browser mounts the component. In other modes it's a compile error.

### Macros

A helper imported with the `type: "macro"` [import attribute](https://github.com/tc39/proposal-import-attributes), the convention [Bun](https://bun.sh/docs/bundler/macros) and [unplugin-macros](https://github.com/unplugin/unplugin-macros) use, may run while the template compiles:

```vue
<script setup lang="ts">
import { button } from "./variants" with { type: "macro" }

const props = defineProps<{ variant?: "solid" | "ghost" }>()
</script>

<template>
  <button :class="button({ variant: props.variant })"><slot /></button>
</template>
```

When everything a call reads is known at compile time, such as a prop a parent passes as a constant (`<Button variant="ghost">`) or doesn't pass at all, the call runs once in QuickBEAM and its result is compiled into the template, so rendering runs no JavaScript. This suits variant helpers such as [tailwind-variants](https://www.tailwind-variants.org). The browser build imports the helper as usual.

When a call reads props known only when rendering, such as `<Button :variant="row.variant">`, and their TypeScript types are finite sets of literals, the call runs once for each combination of values, up to 64, and rendering looks the result up. The types are resolved with TypeScript's own checker from the project's `node_modules`, so a type derived from a variants config works too:

```vue
<script setup lang="ts">
import { badge, type BadgeProps } from "./variants" with { type: "macro" }

// "neutral" | "success" | "warning" | "danger"
const props = defineProps<{ tone?: BadgeProps["tone"] }>()
</script>
```

A value outside the type raises `PhoenixVapor.ExpressionError` when rendering. A call that depends on anything else, such as a prop typed `string`, is a compile error, or a warning in hybrid mode, where the browser renders it.

### Components from assigns

Elsewhere, such as in `~VUE`, a capitalized tag renders a component from the `__components__` assign, a map from tag name to a function that takes assigns and returns rendered content. Default slot content is passed as `inner_block`:

```elixir
assign(socket, __components__: %{"Card" => &MyAppWeb.Components.card/1})
```

```vue
<Card :title="post.title" />
```

## `.vue` files

`use PhoenixVapor, file: "Dashboard.vue"` makes a `.vue` file the LiveView's template. The path is relative to the module's file, and can be any expression known at compile time, such as `Path.join(@templates, "Dashboard.vue")`. Without `ref()` in `<script setup>`, the file is server-only: `render/1` comes from the template, and the rest of the LiveView is your Elixir.

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

## Problems at compile time

Templates compile when the module that uses them does, and problems point into the `.vue` file:

```
** (CompileError) lib/my_app_web/live/Settings.vue:12: can't parse the expression `user.`

warning: <TabsRoot> is imported from "reka-ui", which the server can't render; the browser renders it when it mounts
    │
 24 │     <TabsRoot v-model="tab">
    │     ~~~~~~~~~~~~~~~~~~~~~~~~
    │
    └─ lib/my_app_web/live/Settings.vue:24: (file)
```

What the server can't render is a compile error, except in hybrid mode, where the browser renders it once it mounts, so it's a warning: a [component from a package](#components-from-packages) that can't render on the server, a call to a function `<script setup>` defines or imports, and a [macro](#macros) call that depends on a value known only when rendering.

## Rendering at runtime

`PhoenixVapor.render/2` compiles and renders a template string at runtime, for templates that aren't known at compile time. It parses the template on every call, so prefer the sigil or a `.vue` file when you can.

```elixir
PhoenixVapor.render("<p>{{ msg }}</p>", %{msg: "Hello"})
```
