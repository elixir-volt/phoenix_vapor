// A stand-in for a variants helper such as tailwind-variants: pure, so the
// server can run it at compile time.
type Variant = "solid" | "ghost"

export function button(options: { variant?: Variant; size?: "sm" | "md" }): string {
  const variant = options.variant ?? "solid"
  const size = options.size ?? "md"
  return `btn btn-${variant} btn-${size}`
}

export function card() {
  return { root: () => "card", title: () => "card-title" }
}
