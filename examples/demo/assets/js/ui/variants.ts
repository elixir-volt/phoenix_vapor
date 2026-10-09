import { tv, type VariantProps } from "tailwind-variants"

// Imported by components as a macro, `with { type: "macro" }`: PhoenixVapor
// runs `button(...)` while compiling, once for each value its props' types
// allow, so rendering looks the classes up instead of running JavaScript.
export const button = tv({
  base: "inline-flex items-center justify-center gap-1.5 rounded-md font-medium outline-none transition-opacity focus-visible:ring-2 focus-visible:ring-accent disabled:pointer-events-none disabled:opacity-40",
  variants: {
    variant: {
      primary: "bg-accent text-accent-fg hover:opacity-90",
      secondary: "border border-edge bg-raised text-fg hover:bg-hover",
      ghost: "text-muted hover:bg-raised hover:text-fg"
    },
    size: {
      sm: "h-7 px-3 text-[12.5px]",
      md: "h-8 px-4 text-[13px]"
    }
  },
  defaultVariants: { variant: "secondary", size: "md" }
})

export type ButtonProps = VariantProps<typeof button>
