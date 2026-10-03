# Used by "mix format"
[
  plugins: [Volt.Formatter],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}", "priv/ts/*.ts"],
  # TypeScript under priv/ts, for Volt.Formatter and `mix volt.js.check`.
  volt: [
    root: "priv/ts",
    sources: ["*.ts"],
    print_width: 100,
    semi: false,
    trailing_comma: :none
  ]
]
