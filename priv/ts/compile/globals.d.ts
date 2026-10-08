// Placeholders PhoenixVapor fills in with `Volt.Priv.render!/4` before bundling
// or evaluating a template, and the globals those templates share.
import type { FoldNode } from "./packages.ts"
import type { expressionValues, literalValues } from "./prop-types.ts"

declare global {
  const $imports: unknown
  const $modules: unknown
  const $bindings: unknown
  const $result: unknown
  const $id: string

  /** Macro modules by template file, then by specifier. */
  var __pv_macros: Record<string, Record<string, unknown>> | undefined

  // Entry points PhoenixVapor calls with `QuickBEAM.call/3`, which takes a
  // global function's name.

  /** Renders package components, from `packages.ts`. */
  var __pv_fold_render: (tree: FoldNode) => Promise<string>

  /** The values props can take, from `prop-types.ts`. */
  var __pv_literal_values: typeof literalValues

  /** The values template expressions can take, from `prop-types.ts`. */
  var __pv_expression_values: typeof expressionValues

  /** QuickBEAM's bridge to the handlers the runtime was started with. */
  const Beam: { callSync(handler: string, ...args: unknown[]): unknown }
}
