defmodule PhoenixVaporDemoWeb.ReactiveCounterLive do
  use PhoenixVaporDemoWeb, :live_view
  use PhoenixVapor.Reactive, file: "ReactiveCounter.vue"
end
