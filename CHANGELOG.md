# Changelog

## Unreleased

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
