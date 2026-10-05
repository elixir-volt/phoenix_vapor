[
  import_deps: [:phoenix],
  plugins: [Phoenix.LiveView.HTMLFormatter, Volt.Formatter],
  inputs: [
    "*.{heex,ex,exs}",
    "{config,lib,test}/**/*.{heex,ex,exs}",
    "assets/js/app.ts",
    "assets/js/ui/**/*.ts",
    "test/support/**/*.ts"
  ],
  # TypeScript, for Volt.Formatter and `mix volt.js.check`; generated and
  # bundled files are left out.
  volt: [
    root: ".",
    sources: ["assets/js/app.ts", "assets/js/ui/**/*.ts", "test/support/**/*.ts"],
    print_width: 100,
    semi: false,
    trailing_comma: :none
  ]
]
