defmodule PhoenixVapor.ErrorsTest do
  use ExUnit.Case, async: true

  alias PhoenixVapor.Errors

  describe "to_errors/1" do
    test "accepts flat string-keyed maps" do
      errors = %{"name" => "can't be blank"}

      assert Errors.to_errors(errors) == errors
    end

    test "accepts flat atom-keyed maps" do
      errors = %{name: "can't be blank"}

      assert Errors.to_errors(errors) == errors
    end

    test "accepts error bags" do
      errors = %{"profile" => %{"name" => "can't be blank"}}

      assert Errors.to_errors(errors) == errors
    end

    test "rejects non-string leaf values" do
      assert_raise ArgumentError, ~r/expected string value/, fn ->
        Errors.to_errors(%{"name" => ["can't be blank"]})
      end
    end

    test "rejects non-string and non-atom keys" do
      assert_raise ArgumentError, ~r/expected atom or string key/, fn ->
        Errors.to_errors(%{1 => "can't be blank"})
      end
    end

    test "rejects unsupported values" do
      assert_raise ArgumentError, ~r/expected an error map or Ecto.Changeset/, fn ->
        Errors.to_errors(name: "can't be blank")
      end
    end
  end

  describe "PhoenixVapor.assign_errors/2" do
    test "assigns serialized errors to a socket" do
      socket = %Phoenix.LiveView.Socket{}
      socket = PhoenixVapor.assign_errors(socket, %{"name" => "can't be blank"})

      assert socket.assigns.errors == %{"name" => "can't be blank"}
    end
  end
end
