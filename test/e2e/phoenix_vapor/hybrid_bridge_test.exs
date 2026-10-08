defmodule PhoenixVapor.E2E.HybridBridgeTest do
  # The LiveView hook in priv/ts/browser/hybrid-bridge.ts, driven by a fake
  # LiveView whose replies the test settles, in QuickBEAM.
  use ExUnit.Case, async: true

  @moduletag :e2e
  @moduletag :tmp_dir

  @bridge Path.expand("priv/ts/browser/hybrid-bridge.ts")

  setup %{tmp_dir: tmp_dir} do
    rt = start_supervised!(QuickBEAM)

    File.write!(Path.join(tmp_dir, "entry.ts"), """
    import { createHybridHook } from #{Jason.encode!(@bridge)}

    const applied: unknown[] = []
    const replies: { resolve: (reply: unknown) => void; reject: (error: Error) => void }[] = []
    // What reached the replayer and the server, in order.
    const log: unknown[] = []
    window.addEventListener("phx_replay:state", (event) => log.push(["state", (event as CustomEvent).detail.changes]))
    let bridge: {
      action(event: string, payload: object): void
      record(sources: object, watch: unknown, unref: unknown): void
    }

    const component = {
      __mount(_el: HTMLElement, mounted: typeof bridge) {
        bridge = mounted
        return { applyProps: (props: unknown) => applied.push(props), unmount() {} }
      }
    }

    const hook = createHybridHook({ Tally: component })
    // The hook reads only the wrapper's id and data attributes.
    const el = { id: "pv-Tally", dataset: { pvClient: "Tally", pvProps: JSON.stringify({ saved: 0 }) } }

    const context = Object.assign(Object.create(hook), {
      el,
      pushEvent: (event: string) => {
        log.push(["push", event])
        return new Promise((resolve, reject) => replies.push({ resolve, reject }))
      },
      pushEventTo() {},
      handleEvent() {}
    })
    hook.mounted.call(context)

    // The server's props change, as a diff from the action's answer does.
    const serverSends = (props: object) => {
      el.dataset.pvProps = JSON.stringify(props)
      hook.updated.call(context)
    }

    // A ref the component registers for recording, and Vue's watch, which
    // the test triggers by hand.
    const name = { value: "Acme" }
    const watchers: (() => void)[] = []
    const record = () =>
      bridge.record({ name }, (_getter: unknown, changed: () => void) => {
        watchers.push(changed)
        return () => {}
      }, (source: { value: unknown }) => source.value)
    const type = (value: string) => {
      name.value = value
      for (const changed of watchers) changed()
    }

    Object.assign(globalThis, {
      t: { action: (event: string) => bridge.action(event, {}), serverSends, replies, applied, log, record, type }
    })
    """)

    {:ok, _} =
      Volt.Builder.build(
        entry: Path.join(tmp_dir, "entry.ts"),
        outdir: tmp_dir,
        name: "bundle",
        hash: false,
        sourcemap: false,
        write_manifest: false
      )

    # QuickBEAM has a document but no window; the bridge only listens to it
    # and dispatches on it.
    {:ok, _} = QuickBEAM.eval(rt, "globalThis.window = new EventTarget()")
    # Nor element datasets: <html> says no recording is running.
    {:ok, _} = QuickBEAM.eval(rt, "document.documentElement.dataset = {}")
    {:ok, _} = QuickBEAM.eval(rt, File.read!(Path.join(tmp_dir, "bundle.js")))
    %{rt: rt}
  end

  defp run(rt, js) do
    {:ok, value} = QuickBEAM.eval(rt, "(async () => { #{js} })()")
    value
  end

  test "the props apply once every action in flight is answered", %{rt: rt} do
    # Two actions; the first one's answer brings props without the second's
    # change.
    run(rt, ~s|t.action("first"); t.action("second")|)
    run(rt, ~s|t.serverSends({ saved: 1 })|)
    run(rt, ~s|t.replies[0].resolve({}); await null|)

    assert run(rt, "return t.applied") == []

    run(rt, ~s|t.serverSends({ saved: 2 })|)
    run(rt, ~s|t.replies[1].resolve({}); await null|)

    assert run(rt, "return t.applied") == [%{"saved" => 2}]
  end

  test "an answer that changes nothing still takes back the optimistic change", %{rt: rt} do
    run(rt, ~s|t.action("save"); t.replies[0].resolve({}); await null|)

    assert run(rt, "return t.applied") == [%{"saved" => 0}]
  end

  test "a failed push settles its action too", %{rt: rt} do
    run(
      rt,
      ~s|t.action("save"); t.replies[0].reject(new Error("timeout")); await null; await null|
    )

    assert run(rt, "return t.applied") == [%{"saved" => 0}]
  end

  test "while recorded, state waiting for the next flush goes out before the action", %{rt: rt} do
    run(rt, """
    t.record()
    window.dispatchEvent(new CustomEvent("phx_replay:start", { detail: { state: { flush: 60000 } } }))
    t.type("Acme Labs")
    t.action("saveName")
    """)

    assert run(rt, "return t.log") == [
             ["state", %{"name" => "Acme"}],
             ["state", %{"name" => "Acme Labs"}],
             ["push", "saveName"]
           ]
  end

  test "with no action in flight, the server's props apply at once", %{rt: rt} do
    run(rt, ~s|t.serverSends({ saved: 5 })|)

    assert run(rt, "return t.applied") == [%{"saved" => 5}]
  end
end
