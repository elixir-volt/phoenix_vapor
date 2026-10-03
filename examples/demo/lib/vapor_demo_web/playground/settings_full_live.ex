defmodule VaporDemoWeb.Playground.SettingsFullLive do
  use VaporDemoWeb, :live_view

  use PhoenixVapor,
    file: "ProjectSettings.vue",
    runtime: :full,
    bundle: "priv/js/reka-playground.js",
    globals: %{"reka-ui" => "RekaUI", "tailwind-variants" => "TailwindVariants"}
end
