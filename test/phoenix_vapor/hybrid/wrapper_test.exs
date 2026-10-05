defmodule PhoenixVapor.Hybrid.WrapperTest do
  use ExUnit.Case, async: true

  alias PhoenixVapor.Hybrid.ServerCodegen

  @split Vize.split_template!(~s(<p>{{ title }}</p>))

  defp render(assigns, component_name \\ "Counter") do
    spec = %{
      split: @split,
      client_props: ["title"],
      refs: [],
      values: %{},
      constant: [],
      computeds: [],
      component: component_name
    }

    ServerCodegen.build_rendered(spec, assigns)
  end

  test "a client-owned wrapper is ignored by LiveView patching" do
    [open, close, "</div>"] = render(%{title: "Hi"}).static

    assert open == ~s(<div id="pv-Counter" data-pv data-pv-props=")
    assert close =~ ~s(phx-hook="PhoenixVaporHybrid")
    assert close =~ ~s(phx-update="ignore")
    assert close =~ ~s(data-pv-client="Counter")
  end

  test "a server-only wrapper is patched normally" do
    [_open, close, "</div>"] = render(%{title: "Hi"}, nil).static
    refute close =~ "phx-update"
  end

  test "props are a dynamic, so a prop change keeps the fingerprint" do
    a = render(%{title: "One"})
    b = render(%{title: "Two"})

    assert a.fingerprint == b.fingerprint
    assert [~s({&quot;title&quot;:&quot;One&quot;}), _inner] = a.dynamic.(false)
  end

  test "props are skipped when no client prop changed" do
    assigns = %{title: "Hi", other: 1, __changed__: %{other: true}}
    assert [nil, _inner] = render(assigns).dynamic.(true)

    assigns = %{assigns | __changed__: %{title: true}}
    assert [props, _inner] = render(assigns).dynamic.(true)
    assert props =~ "Hi"
  end
end
