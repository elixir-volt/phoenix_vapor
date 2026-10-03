defmodule PhoenixVapor.DiagnosticsTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  @fixtures Path.expand("../fixtures/diagnostics", __DIR__)

  defmodule RenderErrorLive do
    use Phoenix.LiveView
    use PhoenixVapor, file: "../fixtures/diagnostics/RenderError.vue"
  end

  defp html(rendered), do: rendered |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()

  test "a template that doesn't parse is a compile error at its line in the .vue file" do
    error =
      assert_raise CompileError, fn ->
        defmodule ParseErrorLive do
          use Phoenix.LiveView
          use PhoenixVapor, file: "../fixtures/diagnostics/ParseError.vue"
        end
      end

    assert error.file == Path.join(@fixtures, "ParseError.vue")
    assert error.line == 3
    assert Exception.message(error) =~ "can't parse the expression `a +`"
  end

  test "a warning points at its line in the .vue file" do
    output =
      capture_io(:stderr, fn ->
        defmodule DirectiveLive do
          use Phoenix.LiveView
          use PhoenixVapor, file: "../fixtures/diagnostics/Directive.vue", client_output: nil
        end
      end)

    assert output =~ "the custom directive v-focus doesn't run on the server"
    assert output =~ "Directive.vue:8"
  end

  test "an expression that can't be evaluated raises with where it is" do
    error =
      assert_raise PhoenixVapor.ExpressionError, fn ->
        %{title: "Hi"} |> RenderErrorLive.render() |> html()
      end

    assert error.file == Path.join(@fixtures, "RenderError.vue")
    assert error.position == {8, 11}
    assert Exception.message(error) =~ "RenderError.vue:8:11: can't evaluate `missing()`"
  end

  test "a call to a <script setup> function is a compile error outside hybrid mode" do
    error =
      assert_raise CompileError, fn ->
        defmodule ScriptFunctionLive do
          use Phoenix.LiveView
          use PhoenixVapor, file: "../fixtures/diagnostics/ScriptFunction.vue"
        end
      end

    assert error.line == 8

    assert Exception.message(error) =~
             "`shout(title)` calls shout, which runs only in the browser"
  end

  test "a compiled template inspects as its file and slot count" do
    template =
      "<p>{{ a }}</p>"
      |> Vize.split_template!()
      |> PhoenixVapor.Renderer.compile(file: "Card.vue")

    assert inspect(template) == "#PhoenixVapor.Template<Card.vue, 1 slot>"
  end
end
