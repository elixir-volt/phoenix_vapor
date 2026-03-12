defmodule PhoenixVaporDemoWeb.ReactiveListLive do
  use PhoenixVaporDemoWeb, :live_view
  use PhoenixVapor.Reactive, file: "ReactiveList.vue"
end
