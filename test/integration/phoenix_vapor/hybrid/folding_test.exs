defmodule PhoenixVapor.Integration.Hybrid.FoldingTest do
  # Package components fold at compile time; a session replay renders them
  # from the recorded client state their props read.
  use ExUnit.Case, async: true

  alias PhoenixVapor.Fixtures

  defmodule TabsLive do
    use Phoenix.LiveView
    use PhoenixVapor, file: Fixtures.path("FoldedTabs.vue"), client_output: nil
  end

  test "records the refs only a folded component's props read" do
    assert TabsLive.__hybrid_client_js__() =~ "record({ tab })"
  end
end
