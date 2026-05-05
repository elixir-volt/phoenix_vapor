defmodule VaporDemoWeb.ReactiveListLive do
  use VaporDemoWeb, :live_view
  use PhoenixVapor, file: "ReactiveList.vue", runtime: :reactive
end
