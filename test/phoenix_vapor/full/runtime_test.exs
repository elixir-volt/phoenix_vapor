defmodule PhoenixVapor.VueRuntimeTest do
  use ExUnit.Case, async: false

  alias PhoenixVapor.Full.Runtime

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    bundle = Path.join(tmp_dir, "runtime.js")
    File.write!(bundle, "")

    runtime =
      start_supervised!(
        {Runtime,
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
    assert {:error, error} = Runtime.call(runtime, "throw new Error('call failed')")
    assert inspect(error) =~ "call failed"
    assert {:ok, "<p>ready</p>"} = Runtime.render(runtime)

    assert {:ok, "recovered"} =
             Runtime.call(runtime, "document.body.textContent = 'recovered'")
  end

  test "returns handler errors and keeps successful dispatch working", %{runtime: runtime} do
    assert {:error, error} = Runtime.dispatch(runtime, "fail")
    assert inspect(error) =~ "dispatch failed"
    assert {:ok, "<p>ready</p>"} = Runtime.render(runtime)
    assert {:ok, "updated"} = Runtime.dispatch(runtime, "update", %{"message" => "updated"})
  end

  test "a changed bundle is read again", %{tmp_dir: tmp_dir} do
    bundle = Path.join(tmp_dir, "versioned.js")
    start = &start_supervised!({Runtime, bundle: bundle, setup: ""}, id: &1)

    File.write!(bundle, "document.body.textContent = 'one';")
    assert {:ok, "one"} = Runtime.render(start.(:first))

    File.write!(bundle, "document.body.textContent = 'two, longer';")
    assert {:ok, "two, longer"} = Runtime.render(start.(:second))
  end
end
