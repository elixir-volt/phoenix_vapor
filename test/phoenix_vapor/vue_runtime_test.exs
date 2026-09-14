defmodule PhoenixVapor.VueRuntimeTest do
  use ExUnit.Case, async: false

  alias PhoenixVapor.VueRuntime

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    bundle = Path.join(tmp_dir, "runtime.js")
    File.write!(bundle, "")

    runtime =
      start_supervised!(
        {VueRuntime,
         bundle: bundle,
         setup: """
         document.body.innerHTML = '<p>ready</p>';
         globalThis.__pv_handlers = {
           update: params => { document.body.textContent = params.message; },
           fail: () => { throw new Error('dispatch failed'); }
         };
         """}
      )

    %{runtime: runtime}
  end

  test "returns call errors without replacing them with successful HTML", %{runtime: runtime} do
    assert {:error, error} = VueRuntime.call(runtime, "throw new Error('call failed')")
    assert inspect(error) =~ "call failed"
    assert {:ok, "<p>ready</p>"} = VueRuntime.render(runtime)

    assert {:ok, "recovered"} =
             VueRuntime.call(runtime, "document.body.textContent = 'recovered'")
  end

  test "returns handler errors and keeps successful dispatch working", %{runtime: runtime} do
    assert {:error, error} = VueRuntime.dispatch(runtime, "fail")
    assert inspect(error) =~ "dispatch failed"
    assert {:ok, "<p>ready</p>"} = VueRuntime.render(runtime)
    assert {:ok, "updated"} = VueRuntime.dispatch(runtime, "update", %{"message" => "updated"})
  end
end
