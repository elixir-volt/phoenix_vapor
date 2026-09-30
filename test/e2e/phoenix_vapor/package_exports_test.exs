defmodule PhoenixVapor.E2E.PackageExportsTest do
  use ExUnit.Case, async: true

  @moduletag :e2e
  @moduletag :tmp_dir

  # An application resolves PhoenixVapor's browser modules from deps/.
  test "the package exports bundle from deps", %{tmp_dir: tmp_dir} do
    deps = Path.join(tmp_dir, "deps")
    File.mkdir_p!(deps)
    File.ln_s!(File.cwd!(), Path.join(deps, "phoenix_vapor"))

    File.write!(Path.join(tmp_dir, "app.js"), """
    import { patchLiveSocket, analyzeStatics } from "phoenix_vapor"
    import { getHybridHooks } from "phoenix_vapor/hybrid"
    import { applyDiff } from "phoenix_vapor/vapor-patch"

    globalThis.exported = [patchLiveSocket, analyzeStatics, applyDiff].map((f) => typeof f)
    globalThis.hook = Object.keys(getHybridHooks({}).PhoenixVaporHybrid)
    """)

    assert {:ok, _} =
             Volt.Builder.build(
               entry: Path.join(tmp_dir, "app.js"),
               outdir: tmp_dir,
               resolve_dirs: [deps],
               name: "bundle",
               hash: false,
               sourcemap: false,
               write_manifest: false
             )

    rt = start_supervised!(QuickBEAM)
    assert {:ok, _} = QuickBEAM.eval(rt, File.read!(Path.join(tmp_dir, "bundle.js")))
    assert {:ok, ["function", "function", "function"]} = QuickBEAM.eval(rt, "exported")

    assert {:ok, ["mounted", "updated", "reconnected", "destroyed"]} =
             QuickBEAM.eval(rt, "hook")
  end
end
