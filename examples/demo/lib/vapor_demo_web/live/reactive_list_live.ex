defmodule VaporDemoWeb.ReactiveListLive do
  use VaporDemoWeb, :live_view
  use PhoenixVapor.Reactive, file: "ReactiveList.vue"
end
