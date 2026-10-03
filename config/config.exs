import Config

# JavaScript sources are TypeScript under priv/ts. These settings are for
# `mix format` (through Volt.Formatter) and `mix volt.js.check`.
config :volt, :format,
  root: "priv/ts",
  sources: ["*.ts"],
  print_width: 100,
  semi: false,
  trailing_comma: :none

config :volt, :lint,
  root: "priv/ts",
  sources: ["*.ts"],
  # Installed by `mix npm.install` from the root package.json.
  tsgolint: Path.expand("../node_modules/.bin/tsgolint", __DIR__),
  plugins: ["typescript"],
  env: ["browser"],
  rules: %{
    "correctness" => :deny,
    "typescript/consistent-type-imports" => :deny,
    "typescript/no-floating-promises" => :deny
  },
  overrides: [
    # Compiles the component's <script setup> refs, computeds and handlers,
    # which arrive as source text.
    %{files: ["reactive-runtime.ts"], rules: %{"typescript/no-implied-eval" => :allow}}
  ]
