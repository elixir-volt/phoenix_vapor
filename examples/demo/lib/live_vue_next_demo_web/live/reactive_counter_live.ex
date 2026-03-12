defmodule LiveVueNextDemoWeb.ReactiveCounterLive do
  use LiveVueNextDemoWeb, :live_view
  use LiveVueNext.Reactive, file: "ReactiveCounter.vue"
end
