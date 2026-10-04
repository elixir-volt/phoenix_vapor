# Changelog

## Unreleased

### Breaking changes

- Reactive mode and the full runtime keep their QuickBEAM runtime in `socket.private` instead of the `:__vapor_runtime__` and `:__vue_runtime__` assigns, so a session recorder doesn't record a pid and `render/1` reads only state.
- `PhoenixVapor.Component` and its `vue/1` macro, which returned its argument unchanged, are removed; `use PhoenixVapor` imports only the `~VUE` sigil. Use `~VUE` directly.
- Template expressions follow JavaScript's semantics, as Vue renders them in the browser: truthiness (`0`, `""` and `NaN` are falsy in `v-if`, `? :`, `!`, `&&` and `||`), `===` (`1 === 1.0`), `==`, relational comparison (`undefined > 0` is false), `+` concatenation and arithmetic with `NaN` and `Infinity`, and `typeof null`. A missing assign is `undefined` and `nil` is `null`. Before, Elixir's semantics leaked through, so `v-if="items.length > 0"` rendered with no `items`.
- Modules are grouped by role: `PhoenixVapor.Compiler.*` compiles templates, `PhoenixVapor.Renderer.*` renders them, and each mode's modules sit under it. `PhoenixVapor.Runtime` is now `PhoenixVapor.Reactive.Runtime`, `PhoenixVapor.LiveVue` is `PhoenixVapor.Full`, `PhoenixVapor.VueRuntime` is `PhoenixVapor.Full.Runtime`, and `PhoenixVapor.ScriptSetup` is `PhoenixVapor.Compiler.ScriptSetup`; the runtimes and `ScriptSetup` are internal. `use PhoenixVapor`, `~VUE`, `PhoenixVapor.Vue`, `PhoenixVapor.Template` and `PhoenixVapor.ExpressionError` are unchanged.

### Added

- Session replay for hybrid components: while PhoenixReplay records a session (`PhoenixReplay.recording?/1`), the client reports its refs, debounced, into the `:__pv_refs__` assign; nothing is sent otherwise. Each hybrid LiveView defines `replay_render/1`, which renders without the client hook and with the recorded refs. See the Hybrid guide's Session replay section.
- An expression only JavaScript can evaluate, such as `items.filter(i => i.on)` or `Math.max(a, b)`, is reported at compile time as a warning: it runs in QuickBEAM on every render, while the rest of rendering is Elixir. A method a value doesn't have, such as `trim()` on a number, raises `PhoenixVapor.ExpressionError`, as it throws in the browser.
- In hybrid mode, components from packages, such as Reka UI, render on the server when everything they receive is known at compile time. Vue's server renderer runs them once in QuickBEAM while the template compiles, so rendering runs no JavaScript. Nested package components render together, providers such as `TooltipProvider` render only their content, and in hybrid mode the initial values of refs count as known. One that can't render is reported with the reason, such as a prop known only when rendering or an error from the component. Outside hybrid mode, where nothing takes over in the browser, only package components that render just their content, such as providers, render; others remain a compile error.
- A macro call that reads props known only when rendering runs at compile time once per combination of the values their TypeScript types allow, up to 64, and rendering looks the result up. Types come from TypeScript's own checker, from the project's `node_modules`, so variant types derived from a tailwind-variants config work. A value outside the type raises `PhoenixVapor.ExpressionError`.
- A package component's props may be expressions of known values, such as `:open="selected !== null"` over a ref's initial value, and package parts inside the template's own `v-for` or `v-if`, such as a tooltip per row, render in their ancestors' context.
- A template's call to a `<script setup>` function renders on the server through the function of the same name in snake_case that `<script lang="elixir">` defines, such as `role_tone/1` for `roleTone(role)`. The full runtime now leaves a `<script lang="elixir">` block out of its browser bundle.
- `PhoenixVapor.Volt`, a Volt plugin that resolves `phoenix_vapor` imports from a path or umbrella dependency, which `resolve_dirs: ["deps"]` doesn't find.
- The `file:` option and `PhoenixVapor.Vue.component/2` take any expression known at compile time, such as `Path.join(@templates, "Card.vue")`, besides a path relative to the module's file.

### Fixed

- The QuickBEAM runtime that ran macro calls while compiling was never stopped, and the one for package components leaked when compiling raised. One runtime per compile now serves both and stops in an `after`.
- A hybrid component started a QuickBEAM runtime on every render to evaluate its computed values, and a computed that failed rendered as missing without a report. Computeds now evaluate as template expressions do: one that reads only refs is evaluated once while compiling, and package components can render with it; one that reads props is evaluated when rendering, on the LiveView process's runtime, with its last value reused while its inputs are unchanged. A computed's other computeds are evaluated first, so lists such as a filtered view of props render on the server. A failure is a compile-time warning, or an `ExpressionError` when rendering.
- A template literal's text between expressions rendered empty: `` `a${x}b` `` gave `1`.

## 0.5.0 - 2026-10-03

### Breaking changes

- Require vize 0.17 and Volt 0.20. Vize's `Vize.split_template/2` replaces `vapor_split`. It works from Vize's L2 semantic IR instead of scanning Vapor's template HTML, so PhoenixVapor no longer depends on locating elements in generated HTML. `PhoenixVapor.render/2` takes a template string or a `PhoenixVapor.Template`.
- Compiled templates are `%PhoenixVapor.Template{}` structs, which inspect as their file and slot count, instead of maps.
- An expression that fails when rendering, such as a call to something that isn't a function, raises `PhoenixVapor.ExpressionError` with its file, line, and column, where it rendered nothing.
- A component, function call, or macro call the server can't render is a compile error outside hybrid mode, and a warning in it; it used to render nothing.
- Reactive templates carry `data-vapor-keys` beside `data-vapor-statics`; the browser code in this release reads it.

### Added

- Components imported from `.vue` files render on the server, in every mode: props, slots and scoped slots, `<slot>` fallbacks, and fallthrough attributes merged into the root element.
- Helpers imported with `with { type: "macro" }` run at compile time when their arguments are known then, so variant helpers such as tailwind-variants cost nothing when rendering.
- Compile errors and warnings point to the line in the `.vue` file, and editors show them there.
- Function components from the `__components__` assign receive default slot content as `inner_block`.

### Fixed

- Attributes render as Vue's server renderer does: `null` and a false boolean attribute are left out, where `disabled="false"` made an element disabled, and `class` and `style` take objects and arrays. An object literal such as `:class="{ on: active }"` used to evaluate to nothing.
- `v-show` merges with the element's `style`, and `v-model` renders a checkbox's or radio's `checked` state and a textarea's content.
- `v-for` binds the index, or a map's key and index, to its other aliases.
- Interpolated objects and lists display as JSON, as in Vue.
- A root `v-if` rendered its first branch twice.
- A `v-if`, `v-for` or component re-renders when an assign its content reads changes, not only its condition or source.
- Reactive templates patch text that mixes static text and several values, such as `Doubled: {{ n }} · {{ label }}`, directly, and decode HTML entities in patched text. A diff that also changed a value the patcher couldn't write was half applied.
- A component prop bound to a list or map keeps its value instead of raising.
- Relative imports in a hybrid component's client module resolve from where the module is written.
- Full-runtime components resolve imports through the project's Volt aliases, and a resolution failure raises a readable error.
- Reactive LiveViews recompile when their `.vue` file changes.

## 0.4.0 - 2026-10-03

### Breaking changes

- Require Elixir 1.19, vize 0.16.1, OXC 0.18, QuickBEAM 0.11.2, and Volt 0.19.4, dropping the older versions 0.3.4 also accepted. Volt is now a required dependency, used at compile time only. Building vize from source requires Rust 1.95.
- The browser code is TypeScript in `priv/ts`, exported through the package's `package.json`: import `patchLiveSocket` from `phoenix_vapor` and `getHybridHooks` from `phoenix_vapor/hybrid`. `priv/js/hybrid-bridge.js` is gone, and `patchLiveSocket` was not in the Hex package before.
- A hybrid module exports `__mount(el, bridge, props)`, which returns `applyProps/1` and `unmount/0` for that instance, in place of the module-level `__applyProps`, `__setBridge`, and `__unmount`. Hybrid wrappers are `phx-update="ignore"`, and their server HTML has no `phx-*` event attributes.
- Full-runtime LiveViews take a `:globals` option mapping each package their bundle provides to its global, such as `%{"reka-ui" => "RekaDialog"}`. Only `vue` is mapped by default; `reka-ui` and `@vueuse/*` were hardcoded for the demo's bundle.
- Reactive `mount/3` assigns only the URL params the template reads.
- An unknown `:runtime` option raises at compile time instead of falling back to detecting the mode.

### Added

- A page can mount the same hybrid component several times. Each mount has its own props and bridge.
- `defineProps` is read in its object and TypeScript forms as well as as an array, using Vize's script analysis.
- Guides for getting started and for each mode, and a cheatsheet.

### Changed

- Templates compiled into a module parse their expressions and compute fingerprints at compile time. Rendering a 500-row `v-for` went from 55 ms to 0.5 ms.
- vize 0.16's `vapor_split` reports events and `v-model` as data, and PhoenixVapor renders them as `phx-*` attributes itself.
- The full runtime reads its bundle once and caches it until the file changes, instead of reading it on every mount.
- `@vue/reactivity` for Reactive mode is pinned in `priv/ts/package.json` and vendored by `mix volt.priv.vendor`, replacing a hand-copied build of 3.5.30.
- Slot positions for direct DOM patching come from the browser's HTML parser instead of a hand-written one, which mishandled `>` inside attribute values.
- Scoped CSS uses the scope ID from `Vize.SFC.scope_id/2`, passed to Vize, instead of one read back out of the compiled CSS.

### Fixed

- Hybrid server actions threw in the browser: they referenced `__serverProps` and `triggerRef`, which the generated module never defined.
- Hybrid components re-render when LiveView sends new props. Only the first render used them.
- Hybrid components keep working across server updates, and a prop change sends only the new props JSON instead of the whole tree.
- Hybrid components get every prop the template or client-side code reads. Props used only in the template were left out, so they rendered empty once the client mounted.
- Server actions send the values of refs and computeds instead of serialized `Ref` objects.
- Before the client mounted, LiveView acted on hybrid `phx-click` attributes such as `phx-click="pick(c)"` and pushed the handler source to the server as an event name.
- The hybrid bridge applies the initial props before mounting and unmounts the component when the hook is destroyed.
- A QuickBEAM runtime leaked on every hybrid render.
- Rendering never creates atoms. Reactive `mount/3` turned every URL param into an atom, and change tracking, component props, `v-for` variables, and hybrid props and computeds converted names at render time, which `PhoenixVapor.render/2` does for templates built at runtime.
- Computeds may read computeds declared after them, and block-bodied computeds work in Reactive mode.
- Expressions with methods that aren't evaluated in Elixir fall back to QuickBEAM. `list.filter(fun)` and `list.map(fun)` with a function reference returned the list unchanged, and methods such as `padStart` rendered nothing.
- Scope and Vapor metadata attributes go after the root tag's name. They were inserted before the first `>`, which could be inside an attribute value such as `title="a > b"`.
- A `<script lang="elixir">` block is left out of the hybrid client module, even after `<script setup>`.
- Full-runtime LiveViews raise the JavaScript error from mount and events instead of a `MatchError`.
- The Hex package contains only PhoenixVapor's own JavaScript. It included all of `priv/js`, so a locally built bundle such as `reka-dialog.js` would have been published.

## 0.3.4 - 2026-09-30

### Compatibility

- Support Volt 0.19, OXC 0.18, and Vize 0.15, alongside the versions supported before.

## 0.3.3 - 2026-09-15

### Fixed

- Return JavaScript evaluation errors from full-runtime calls and event dispatches instead of reporting successful stale HTML.

### Compatibility

- Support Volt 0.17.11 and the 0.18 series with QuickBEAM 0.11.1 or later in the 0.11 series, resolving the shared dependency conflict when adding PhoenixVapor to a current Volt application.

## 0.3.2 - 2026-08-24

### Added

- Allow full-runtime LiveViews to override and compose generated lifecycle callbacks with `super`.

### Fixed

- Preserve document order when rendering nested property, text, and structural Vapor slots.
- Capture the full-runtime SFC component export reliably before mounting it.
- Resolve relative `.vue` imports from the source component directory in full-runtime mode.

## 0.3.1 - 2026-08-17

### Fixed

- Corrected duplicate static text when rendering interpolations with Vize 0.14.

### Compatibility

- Updated Phoenix Vapor to work with Volt 0.17, OXC 0.17, Vize 0.14, and Phoenix LiveView 1.2.
