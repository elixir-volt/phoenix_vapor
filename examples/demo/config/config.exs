# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :phoenix_vapor_demo,
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :phoenix_vapor_demo, PhoenixVaporDemoWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: PhoenixVaporDemoWeb.ErrorHTML, json: PhoenixVaporDemoWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: PhoenixVaporDemo.PubSub,
  live_view: [signing_salt: "qQeZE5Bm"]

# Configure Volt (replaces esbuild + tailwind)
config :volt,
  entry: "assets/js/app.js",
  outdir: "priv/static/assets",
  root: "assets",
  sources: ["**/*.{js,ts,jsx,tsx,vue}"],
  target: :es2022,
  minify: false,
  hash: false,
  resolve_dirs: ["node_modules", "deps"],
  aliases: %{"vue" => "node_modules/vue/dist/vue.runtime-with-vapor.esm-browser.js"},
  tailwind: [
    css: "assets/css/app.css",
    sources: [
      %{base: "lib/", pattern: "**/*.{ex,heex}"},
      %{base: "assets/", pattern: "**/*.{js,ts,vue}"}
    ]
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
