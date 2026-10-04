// Placeholders PhoenixVapor fills in with `Volt.Priv.render!/4` before bundling
// or evaluating a template, and the globals those templates share.
import type { FoldNode } from "./fold-renderer.ts"

declare global {
  const $imports: unknown
  const $modules: unknown
  const $bindings: unknown
  const $result: unknown
  const $id: string

  /** Macro modules by template file, then by specifier. */
  var __pv_macros: Record<string, Record<string, unknown>> | undefined

  /** The package component renderer, from `fold-renderer.ts`. */
  var __pv_fold: { render: (tree: FoldNode) => Promise<string> } | undefined
}
