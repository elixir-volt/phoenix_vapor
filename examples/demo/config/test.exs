import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :vapor_demo, VaporDemoWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "gHHPjpIgBsbcU761ZFj0ocsApRFavdCHtLoYAHLe3btHkuRqfUFEtOLj7q1Qbs+J",
  server: true

config :phoenix_test, otp_app: :vapor_demo

config :volt, :server, prefix: "/assets"

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

config :phoenix_test, playwright: [assets_dir: "."]

# Counts reactive patches in the browser, for the end-to-end tests.
config :vapor_demo, vapor_debug: true

# Session replay records nothing in tests, but the replay test turns it on,
# into a directory of its own.
config :phoenix_replay,
  sample_rate: 0.0,
  storage: {PhoenixReplay.Storage.File, path: Path.expand("../tmp/replay_recordings", __DIR__)}

# The session replay dashboard, for the test that replays a recording.
config :vapor_demo, dev_routes: true
