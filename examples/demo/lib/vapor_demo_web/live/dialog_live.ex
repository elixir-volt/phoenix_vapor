defmodule VaporDemoWeb.DialogLive do
  use VaporDemoWeb, :live_view
  use PhoenixVapor,
    file: "Dialog.vue",
    runtime: :full,
    bundle: "priv/js/reka-dialog.js"
end
