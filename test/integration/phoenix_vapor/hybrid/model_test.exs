defmodule PhoenixVapor.Integration.Hybrid.ModelTest do
  # A prop the browser changes, and the server owns, is a model.
  use ExUnit.Case, async: true

  alias PhoenixVapor.Fixtures

  @moduletag :integration

  @contacts [%{"id" => 1, "name" => "Ada"}, %{"id" => 2, "name" => "Bob"}]

  defmodule ContactsLive do
    use Phoenix.LiveView
    use PhoenixVapor, file: Fixtures.path("HybridModel.vue"), client_output: nil
  end

  defp html(rendered), do: rendered |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()

  defp compile(fixture) do
    Code.compile_quoted(
      quote do
        defmodule unquote(Module.concat(__MODULE__, "Live#{System.unique_integer([:positive])}")) do
          use Phoenix.LiveView
          use PhoenixVapor, file: unquote(Fixtures.path(fixture)), client_output: nil
        end
      end
    )
  end

  test "the server renders a model from its assign, and computeds read it as .value" do
    html = ContactsLive.render(%{title: "Team", contacts: @contacts, __changed__: nil}) |> html()

    assert html =~ "<h1>Team</h1>"
    assert html =~ "2 of 2"
    assert html =~ "Ada"
  end

  test "the browser gets the model with the props" do
    c = ContactsLive.__hybrid_classification__()

    assert c.models == ["contacts"]
    assert "contacts" in c.client_props

    html = ContactsLive.render(%{title: "Team", contacts: @contacts, __changed__: nil}) |> html()
    assert html =~ "&quot;contacts&quot;:[{"
  end

  test "a function that writes a model is a server action" do
    assert {:server_action, _body} =
             ContactsLive.__hybrid_classification__().handlers["deleteContact"]
  end

  test "the action's body runs in the browser, then the action goes to the server" do
    js = ContactsLive.__hybrid_client_js__()

    assert js =~ "contacts.value = contacts.value.filter"
    assert js =~ ~s|const __pvParams = JSON.parse(JSON.stringify({"id": id}));|
    assert js =~ ~s|__pv.bridge.action("deleteContact", __pvParams);|
    # The mount applies the model's update to its props.
    assert js =~ ~s|const __models = ["contacts"];|
    assert js =~ ~s|"onUpdate:" + model|
    assert {:ok, _ast} = OXC.parse(js, "client.js")
  end

  test "a model isn't client state to record" do
    refute ContactsLive.__hybrid_client_js__() =~ "record({ contacts"
  end

  test "writing a prop is a compile error that points at defineModel" do
    error = assert_raise CompileError, fn -> compile("diagnostics/HybridPropWrite.vue") end

    assert Exception.message(error) =~ "HybridPropWrite.vue:9"
    assert Exception.message(error) =~ "the prop `items` is written, but props are read-only"
    assert Exception.message(error) =~ ~s|const items = defineModel("items")|
  end

  test "writing a prop the script never declares is a compile error too" do
    error = assert_raise CompileError, fn -> compile("diagnostics/HybridBarePropWrite.vue") end

    assert Exception.message(error) =~ "HybridBarePropWrite.vue:15"
    assert Exception.message(error) =~ "the prop `users` is written"
  end

  test "a model must be named after its variable" do
    error = assert_raise CompileError, fn -> compile("diagnostics/HybridUnnamedModel.vue") end

    assert Exception.message(error) =~ "HybridUnnamedModel.vue:2"
    assert Exception.message(error) =~ "the model `modelValue` is bound to `open`"
  end
end
