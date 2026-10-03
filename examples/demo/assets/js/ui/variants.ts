import { tv, type VariantProps } from "tailwind-variants"

export const button = tv({
  base: "inline-flex items-center justify-center gap-2 rounded-md text-sm font-medium transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-indigo-500 disabled:pointer-events-none disabled:opacity-50",
  variants: {
    variant: {
      default: "bg-zinc-900 text-white hover:bg-zinc-800",
      destructive: "bg-red-600 text-white hover:bg-red-500",
      outline: "border border-zinc-300 bg-white hover:bg-zinc-100",
      ghost: "hover:bg-zinc-100",
    },
    size: {
      sm: "h-8 px-3",
      md: "h-9 px-4",
      lg: "h-10 px-6",
    },
  },
  defaultVariants: { variant: "default", size: "md" },
})

export const badge = tv({
  base: "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-semibold",
  variants: {
    tone: {
      neutral: "bg-zinc-100 text-zinc-700",
      success: "bg-emerald-100 text-emerald-700",
      warning: "bg-amber-100 text-amber-800",
      danger: "bg-red-100 text-red-700",
    },
  },
  defaultVariants: { tone: "neutral" },
})

export const card = tv({
  slots: {
    root: "rounded-lg border border-zinc-200 bg-white shadow-sm",
    header: "border-b border-zinc-100 px-5 py-4",
    title: "text-base font-semibold text-zinc-900",
    description: "text-sm text-zinc-500",
    body: "px-5 py-4",
  },
})

export type ButtonProps = VariantProps<typeof button>
export type BadgeProps = VariantProps<typeof badge>
