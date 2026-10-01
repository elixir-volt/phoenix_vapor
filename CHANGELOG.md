# Changelog

## Unreleased

### Fixed

- Hybrid server actions no longer throw in the browser. They referenced `__serverProps` and `triggerRef`, which the generated module never defined.
- Re-render hybrid components when LiveView sends new props. Only the first render used them.
- Keep hybrid components working across server updates. The wrapper is now `phx-update="ignore"`, and the props JSON is a dynamic instead of part of the statics, so a prop change no longer resends the whole tree.
- Send the values of refs and computeds in server action params, instead of serialized `Ref` objects.
- The bundled hybrid bridge applies the initial props before mounting and unmounts the component when the hook is destroyed.
- Stop leaking a QuickBEAM runtime on every hybrid render.
- Reactive `mount/3` no longer creates atoms from URL params. Only params the template reads become assigns.
- Computeds may read computeds declared after them, and block-bodied computeds work in Reactive mode.
- Put scope and Vapor metadata attributes after the root tag's name. They were inserted before the first `>`, which landed inside an attribute value such as `title="a > b"`.
- Scoped CSS uses the scope id from `Vize.SFC.scope_id/2`, passed to Vize, instead of one read back out of the compiled CSS.
- Leave a `<script lang="elixir">` block out of the hybrid client module when it follows `<script setup>`. The block was cut from the first `<script` tag.
- Full-runtime LiveViews raise the JavaScript error from mount and events instead of a `MatchError`.
- An unknown `:runtime` option is a compile error. It used to fall back to detecting the mode.
- Hybrid components get every prop the template or client-side code reads. Props used only in the template were left out of `data-pv-props`, so the client rendered them empty once it mounted.
- Read `defineProps` in its object and TypeScript forms, not only as an array, using Vize's script analysis.
- A page can mount the same hybrid component several times. Each mount has its own props and bridge.
- Publish only PhoenixVapor's own JavaScript files. The Hex package included all of `priv/js`, so a locally built bundle such as `reka-dialog.js` would have been published with it.
- Point the README install snippet and the bundle task's error message at the current QuickBEAM and Volt versions.

### Changed

- Full-runtime LiveViews take a `:globals` option mapping each package the bundle provides to its global, such as `%{"reka-ui" => "RekaDialog"}`. The map was hardcoded for the demo's Reka bundle, including two `@vueuse` globals the bundle never defined.
- The full runtime reads its bundle once and caches it until the file changes, instead of reading it from disk on every mount.
- Templates compiled into a module parse their expressions and compute fingerprints at compile time. Rendering a 500-row `v-for` went from 55 ms to 0.5 ms.
- A hybrid module exports `__mount(el, bridge, props)`, which returns `applyProps/1` and `unmount/0` for that instance, in place of the module-level `__applyProps`, `__setBridge` and `__unmount`. The bundled bridge uses it.
- The browser and QuickBEAM code is TypeScript in `priv/ts`, built with Volt. Import it as `phoenix_vapor` (`patchLiveSocket`), `phoenix_vapor/hybrid` (`getHybridHooks`) and `phoenix_vapor/vapor-patch`. `patchLiveSocket` was not in the Hex package before.
- `@vue/reactivity` for reactive mode is pinned in `priv/ts/package.json` and vendored by `mix volt.priv.vendor`, replacing a hand-copied build of 3.5.30.
- Slot positions for direct DOM patching come from the browser's HTML parser instead of a hand-written one, which mishandled `>` inside attribute values.
- Volt is a required dependency (compile time only).

### Compatibility

- Require Elixir 1.19. vize 0.15 already did, so earlier versions could not resolve the dependencies.
- Require vize 0.15, OXC 0.18, QuickBEAM 0.11.2 and Volt 0.19, dropping the older versions 0.3.4 also accepted. Building vize from source requires Rust 1.95.

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
