defmodule VaporDemoWeb.ReactiveCounterLive do
  use VaporDemoWeb, :live_view
  use PhoenixVapor.Reactive, file: "ReactiveCounter.vue"
end
