defmodule PhoenixVaporDemoWeb.DialogLive do
  use PhoenixVaporDemoWeb, :live_view
  use PhoenixVapor.LiveVue,
    file: "Dialog.vue",
    bundle: "priv/js/reka-dialog.js"
end
