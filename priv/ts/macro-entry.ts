// Loads the modules a template imports macros from. PhoenixVapor fills
// `$imports` with them, `$modules` with them by specifier, and `$id` with the
// template's file, then bundles this file with the template's `node_modules`.
$imports

globalThis.__pv_macros ??= {}
globalThis.__pv_macros[$id] = { $modules }
