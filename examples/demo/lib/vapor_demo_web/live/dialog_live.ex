defmodule VaporDemoWeb.DialogLive do
  use VaporDemoWeb, :live_view
  use PhoenixVapor.LiveVue,
    file: "Dialog.vue",
    bundle: "priv/js/reka-dialog.js"
end
