import Config

# JavaScript sources are TypeScript under priv/ts, formatted through the
# `volt:` options in .formatter.exs. These settings are for `mix volt.js.check`.
config :volt, :lint,
  root: "priv/ts",
  sources: ["{browser,reactive,compile}/**/*.ts"],
  # Installed by `mix npm.install` from the root package.json.
  tsgolint: "node_modules/.bin/tsgolint",
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
    %{files: ["reactive/runtime.ts"], rules: %{"typescript/no-implied-eval" => :allow}},
    # Templates whose `$name` placeholder statements PhoenixVapor replaces.
    %{
      files: ["compile/packages.ts", "compile/macros/call.ts", "compile/macros/entry.ts"],
      rules: %{"no-unused-expressions" => :allow}
    }
  ]
