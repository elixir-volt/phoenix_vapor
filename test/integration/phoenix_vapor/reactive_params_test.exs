defmodule PhoenixVapor.Integration.ReactiveParamsTest do
  use ExUnit.Case, async: true

  defmodule GreetingLive do
    use Phoenix.LiveView
    use PhoenixVapor, file: "../../fixtures/Greeting.vue", runtime: :reactive
  end

  defp mount(params) do
    {:ok, socket} = GreetingLive.mount(params, %{}, %Phoenix.LiveView.Socket{})
    socket.assigns
  end

  test "params the template reads become assigns" do
    assert %{name: "Ann", count: 0} = mount(%{"name" => "Ann"})
  end

  test "other params are dropped without creating atoms" do
    key = "pv_param_#{System.unique_integer([:positive])}"
    assigns = mount(%{"name" => "Ann", key => "x"})

    refute Map.has_key?(assigns, key)
    assert_raise ArgumentError, fn -> String.to_existing_atom(key) end
  end

  test "mounting outside the router" do
    assert %{count: 0} = mount(:not_mounted_at_router)
  end
end
