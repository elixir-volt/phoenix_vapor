// What importing a .vue file gives TypeScript: a component. Volt type-checks
// each component's script, not its template, so this is as precise as an
// import of one gets there.
declare module "*.vue" {
  import type { DefineComponent } from "vue"

  const component: DefineComponent
  export default component
}
