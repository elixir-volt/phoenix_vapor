defmodule VaporDemoWeb.Modes.ReactiveLive do
  @moduledoc """
  A LiveView that is one `.vue` file: its `ref()`s, computeds and handlers
  run on the server, in QuickBEAM.
  """

  use VaporDemoWeb, :live_view
  use PhoenixVapor, file: "ReactiveCounter.vue", runtime: :reactive
end
