# Changelog

## Unreleased

### Fixed

- Render `v-html`. Vize dropped the `set_html` slot, so the element rendered empty; vize 0.15.0 keeps it.
- Hybrid server actions no longer throw in the browser. They referenced `__serverProps` and `triggerRef`, which the generated module never defined.
- Re-render hybrid components when LiveView sends new props. Only the first render used them.
- Keep hybrid components working across server updates. The wrapper is now `phx-update="ignore"`, and the props JSON is a dynamic instead of part of the statics, so a prop change no longer resends the whole tree.
- Send the values of refs and computeds in server action params, instead of serialized `Ref` objects.
- The bundled hybrid bridge applies the initial props before mounting and unmounts the component when the hook is destroyed.
- Stop leaking a QuickBEAM runtime on every hybrid render.
- Reactive `mount/3` no longer creates atoms from URL params. Only params the template reads become assigns.
- Computeds may read computeds declared after them, and block-bodied computeds work in Reactive mode.
- Publish only PhoenixVapor's own JavaScript files. The Hex package included all of `priv/js`, so a locally built bundle such as `reka-dialog.js` would have been published with it.
- Point the README install snippet and the bundle task's error message at the current QuickBEAM and Volt versions.

### Compatibility

- Require Elixir 1.19. vize 0.15 already did, so earlier versions could not resolve the dependencies.
- Require vize 0.15.0, OXC 0.18.1, and QuickBEAM 0.11.2 or later in the 0.11 series, and support Volt 0.19, matching the dependencies Volt 0.19 resolves. Building vize from source now requires Rust 1.95.

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
