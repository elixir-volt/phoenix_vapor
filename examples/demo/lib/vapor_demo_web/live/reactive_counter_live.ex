defmodule VaporDemoWeb.ReactiveCounterLive do
  use VaporDemoWeb, :live_view
  use PhoenixVapor, file: "ReactiveCounter.vue", runtime: :reactive
end
