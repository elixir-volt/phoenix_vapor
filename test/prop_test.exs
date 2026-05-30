defmodule PhoenixVapor.PropTest do
  use ExUnit.Case, async: true

  alias PhoenixVapor.Prop

  describe "helpers" do
    test "always wraps a value" do
      assert %Prop.Always{value: 1} = Prop.always(1)
    end

    test "optional wraps a zero-arity function" do
      fun = fn -> 1 end
      assert %Prop.Optional{fun: ^fun} = Prop.optional(fun)
    end

    test "optional rejects non-functions" do
      assert_raise ArgumentError, ~r/zero-arity function/, fn ->
        Prop.optional(1)
      end
    end

    test "defer wraps a zero-arity function with a default group" do
      fun = fn -> 1 end
      assert %Prop.Defer{fun: ^fun, group: "default"} = Prop.defer(fun)
    end

    test "defer accepts a custom group" do
      fun = fn -> 1 end
      assert %Prop.Defer{fun: ^fun, group: "dashboard"} = Prop.defer(fun, "dashboard")
    end

    test "defer rejects invalid arguments" do
      assert_raise ArgumentError, ~r/zero-arity function and string group/, fn ->
        Prop.defer(1)
      end
    end

    test "preserve_case marks a key" do
      assert Prop.preserve_case(:user_id) == {:preserve, :user_id}
    end
  end

  describe "PhoenixVapor.assign_prop/3" do
    test "stores props in reserved socket assigns" do
      socket = %Phoenix.LiveView.Socket{}
      socket = PhoenixVapor.assign_prop(socket, :countries, ["US"])

      assert socket.assigns.__pv_props__ == %{countries: ["US"]}
    end
  end
end
