// Renders components from packages, such as Reka UI, with Vue's server renderer
// while PhoenixVapor compiles a template. PhoenixVapor fills `$imports` with the
// packages the template imports components from, and `$modules` with them by
// specifier, then bundles this file with the template's own `node_modules`.
import { createSSRApp, createStaticVNode, h, type Component, type VNode } from "vue"
import { renderToString } from "vue/server-renderer"

$imports

/**
 * A package component to render: its props, and the content of each of its
 * slots as HTML or nested package components.
 */
export interface FoldNode {
  source: string
  name: string
  props: Record<string, unknown>
  slots: Record<string, Array<string | FoldNode>>
}

const modules = { $modules } as unknown as Record<string, Record<string, Component>>

function build(node: FoldNode): VNode {
  const component = modules[node.source]?.[node.name]
  if (!component) throw new Error(`${node.source} has no export ${node.name}`)

  const slots: Record<string, () => VNode[]> = {}
  for (const [name, parts] of Object.entries(node.slots)) {
    slots[name] = () =>
      parts.map((part) => (typeof part === "string" ? createStaticVNode(part, 0) : build(part)))
  }

  return h(component, node.props, slots)
}

/**
 * Renders a tree to HTML. An error or warning while rendering means the output
 * can't be trusted, such as a part rendered without the parent whose context it
 * needs. Vue catches what its handlers throw, so they collect the problems, and
 * the first one rejects the result.
 */
export function render(tree: FoldNode): Promise<string> {
  const problems: string[] = []
  const app = createSSRApp({ render: () => build(tree) })
  app.config.errorHandler = (error) => {
    problems.push(error instanceof Error ? error.message : String(error))
  }
  app.config.warnHandler = (message) => {
    problems.push(message)
  }

  return renderToString(app).then((html) => {
    const [problem] = problems
    if (problem !== undefined) throw new Error(problem)
    return html
  })
}

globalThis.__pv_fold = { render }
