defmodule VaporDemoWeb.Modes.FullLive do
  @moduledoc """
  The full runtime: Vue itself renders the component on the server, in
  QuickBEAM, with a component library bundled for it.
  """

  use VaporDemoWeb, :live_view

  use PhoenixVapor,
    file: "Dialog.vue",
    runtime: :full,
    bundle: "priv/js/reka-dialog.js",
    globals: %{"reka-ui" => "RekaDialog"}
end
