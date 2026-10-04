defmodule PhoenixVapor.RuntimeComputedOrderTest do
  use ExUnit.Case, async: true

  alias PhoenixVapor.Reactive.Runtime

  test "a computed can read one that sorts after it" do
    {:ok, rt} =
      start_supervised(
        {Runtime,
         refs: %{"count" => "1"},
         computeds: %{"a_label" => "\"n=\" + z_doubled", "z_doubled" => "count * 2"}}
      )

    assert {:ok, %{"a_label" => "n=2", "z_doubled" => 2}} = Runtime.get_state(rt)
  end

  test "block-bodied computeds" do
    {:ok, rt} =
      start_supervised(
        {Runtime,
         refs: %{"items" => "[1, 2, 3]"},
         computeds: %{"total" => "{ let sum = 0; for (const i of items) sum += i; return sum }"}}
      )

    assert {:ok, %{"total" => 6}} = Runtime.get_state(rt)
  end
end
