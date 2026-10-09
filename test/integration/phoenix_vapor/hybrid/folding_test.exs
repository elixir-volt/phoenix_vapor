defmodule PhoenixVapor.Integration.Hybrid.FoldingTest do
  # A package component whose props read client state folds at compile time
  # once for each value their types allow, so a session replay renders it as
  # the recorded state had it.
  use ExUnit.Case, async: true

  alias PhoenixVapor.{Compiler, Fixtures, Template}
  alias PhoenixVapor.Compiler.SFC

  defmodule TabsLive do
    use Phoenix.LiveView
    use PhoenixVapor, file: Fixtures.path("FoldedTabs.vue"), client_output: nil
  end

  defmodule DialogLive do
    use Phoenix.LiveView
    use PhoenixVapor, file: Fixtures.path("FoldedDialog.vue"), client_output: nil
  end

  defmodule SwitchLive do
    use Phoenix.LiveView
    use PhoenixVapor, file: Fixtures.path("FoldedSwitch.vue"), client_output: nil
  end

  defmodule ChildLive do
    use Phoenix.LiveView
    use PhoenixVapor, file: Fixtures.path("FoldedChild.vue"), client_output: nil
  end

  defmodule PassedLive do
    use Phoenix.LiveView
    use PhoenixVapor, file: Fixtures.path("FoldedPassed.vue"), client_output: nil
  end

  defmodule ComposableLive do
    use Phoenix.LiveView
    use PhoenixVapor, file: Fixtures.path("FoldedComposable.vue"), client_output: nil
  end

  defmodule NumberLive do
    use Phoenix.LiveView
    use PhoenixVapor, file: Fixtures.path("FoldedNumber.vue"), client_output: nil
  end

  defp html(rendered), do: rendered |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()

  # A replayer's render of one moment, with the client state recorded then.
  defp replay(live, component, assigns, state) do
    assigns
    |> Map.merge(%{
      phoenix_replay_state: %{"phoenix_vapor:pv-#{component}" => state},
      __changed__: nil
    })
    |> live.replay_render()
    |> html()
  end

  defp compile(name) do
    {template, _files, diagnostics} =
      Compiler.compile(SFC.read!(Fixtures.path("#{name}.vue")), target: :browser)

    {fragments(template), diagnostics}
  end

  defp fragments(%{slots: slots}) do
    Enum.flat_map(slots, fn slot ->
      own = if slot.kind == :fragments, do: [slot], else: []
      own ++ Enum.flat_map(Template.blocks(slot), &fragments/1)
    end)
  end

  defp variants(%{inputs: inputs, table: table}),
    do: {Enum.map(inputs, &elem(&1, 1)), table |> Map.keys() |> Enum.sort()}

  describe "variants" do
    test "one for each value of a ref typed as a union of literals" do
      assert {[fragments], []} = compile("FoldedTabs")
      assert variants(fragments) == {["tab"], [["general"], ["members"], ["notifications"]]}
    end

    test "one for each value of an expression's type, such as a comparison" do
      assert {[fragments], []} = compile("FoldedDialog")
      assert variants(fragments) == {["target !== null"], [[false], [true]]}
    end

    test "one for each value of a type TypeScript infers" do
      assert {[fragments], []} = compile("FoldedSwitch")
      assert variants(fragments) == {["notify"], [[false], [true]]}
    end

    test "one for each value of the parent's expression a child component's prop reads" do
      assert {[], []} = compile("FoldedPassed")

      {template, _files, []} =
        Compiler.compile(SFC.read!(Fixtures.path("FoldedPassed.vue")), target: :browser)

      assert [%{kind: :component, component: %{template: child}}] = template.slots
      assert [fragments] = fragments(child)
      assert variants(fragments) == {["model"], [["a"], ["b"]]}
    end

    test "nested package components take part in the same combinations" do
      assert {[fragments], []} = compile("components/PackageFold")
      assert {inputs, combinations} = variants(fragments)
      assert inputs == ["tab", "confirming"]
      assert length(combinations) == 4
    end
  end

  describe "a fold with the initial values" do
    test "when a type isn't a finite set of values" do
      assert {[], [diagnostic]} = compile("FoldedString")
      assert diagnostic.severity == :unrendered

      assert diagnostic.message ==
               ~s(<TabsRoot> folds with the initial value of `model-value`: `query` is string; ) <>
                 ~s(declare its type as a union of literals, such as ref<"a" | "b">(...\), to fold it for each value)
    end

    test "when there are more combinations than 64" do
      assert {[], [diagnostic]} = compile("FoldedMany")
      assert diagnostic.severity == :unrendered

      assert diagnostic.message ==
               "<ConfigProvider> folds with the initial values of its props: " <>
                 "`a`, `b`, `c`, `d`, `e`, `f`, `g` can take 128 combinations of values, more than 64"
    end
  end

  describe "a replay" do
    test "records the refs only a folded component's props read" do
      assert TabsLive.__hybrid_client_js__() =~ "record({ tab })"
      assert DialogLive.__hybrid_client_js__() =~ "record({ target })"
      assert SwitchLive.__hybrid_client_js__() =~ "record({ notify })"
    end

    test "follows the recorded tab" do
      for {tab, label} <- [{"general", "General"}, {"members", "Members"}] do
        html = replay(TabsLive, "FoldedTabs", %{name: "Ada"}, %{"tab" => tab})
        assert html =~ ~r/aria-selected="true" data-state="active">#{label}</
      end

      html = replay(TabsLive, "FoldedTabs", %{name: "Ada"}, %{"tab" => "members"})
      assert html =~ "<p>Members of Ada</p>"
      refute html =~ "<p>Hello Ada</p>"
    end

    test "follows the recorded dialog target" do
      contacts = [%{"id" => 1, "name" => "Ann"}]

      closed = replay(DialogLive, "FoldedDialog", %{contacts: contacts}, %{"target" => nil})
      refute closed =~ ~s(role="dialog")

      open =
        replay(DialogLive, "FoldedDialog", %{contacts: contacts}, %{
          "target" => %{"id" => 1, "name" => "Ann"}
        })

      assert open =~ ~s(role="dialog")
      assert open =~ "Remove Ann?"
    end

    test "follows the recorded switch" do
      assert replay(SwitchLive, "FoldedSwitch", %{}, %{"notify" => true}) =~
               ~s(aria-checked="true")

      assert replay(SwitchLive, "FoldedSwitch", %{}, %{"notify" => false}) =~
               ~s(aria-checked="false")
    end

    test "follows a model a child component passes to a folded component" do
      assert ChildLive.__hybrid_client_js__() =~ "record({ alerts })"

      for {alerts, checked} <- [{true, "true"}, {false, "false"}] do
        html = replay(ChildLive, "FoldedChild", %{}, %{"alerts" => alerts})
        assert html =~ ~r/<button[^>]*id="alerts"[^>]*aria-checked="#{checked}"/
      end
    end

    test "follows a ref the parent passes a child component as its model" do
      for tab <- ["a", "b"] do
        html = replay(PassedLive, "FoldedPassed", %{}, %{"choice" => tab})
        assert html =~ ~r/<button[^>]*trigger-#{tab}"[^>]*aria-selected="true"/
      end
    end

    test "without recorded state renders the initial values" do
      assert replay(TabsLive, "FoldedTabs", %{name: "Ada"}, %{}) =~ "<p>Hello Ada</p>"
    end

    test "of a value its type doesn't allow renders the initial values, with a warning" do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          html = replay(TabsLive, "FoldedTabs", %{name: "Ada"}, %{"tab" => "billing"})
          assert html =~ "<p>Hello Ada</p>"
        end)

      assert log =~ ~s(`tab` is "billing", which its type doesn't allow)
    end

    test "of a whole float matches the integer it equals" do
      html = replay(NumberLive, "FoldedNumber", %{}, %{"step" => 50.0})
      assert html =~ ~s(aria-valuenow="50")
    end
  end

  describe "composable state" do
    test "folds for each value of its type" do
      assert {[fragments], []} = compile("FoldedComposable")
      assert variants(fragments) == {["tab"], [["a"], ["b"]]}
    end

    test "the first render, which doesn't have it, leaves the component to the browser" do
      html = ComposableLive.render(%{__changed__: nil}) |> html()
      refute html =~ "role=\"tablist\""
    end

    test "a replay renders the recorded value" do
      html = replay(ComposableLive, "FoldedComposable", %{}, %{"tab" => "b"})
      assert html =~ ~r/<button[^>]*trigger-b"[^>]*aria-selected="true"/
    end
  end

  describe "live" do
    defmodule ValuesLive do
      use Phoenix.LiveView
      use PhoenixVapor, file: Fixtures.path("components/PackageValues.vue")
    end

    test "a hybrid render is the initial values' variant" do
      html = TabsLive.render(%{name: "Ada", __changed__: nil}) |> html()
      assert html =~ ~r/aria-selected="true" data-state="active">General</
    end

    test "a fragment re-renders when what its inputs read changes" do
      unchanged = ValuesLive.render(%{open: true, __changed__: %{}})
      assert unchanged.dynamic.(true) == [nil]

      changed = ValuesLive.render(%{open: false, __changed__: %{open: true}})
      assert [%Phoenix.LiveView.Rendered{}] = changed.dynamic.(true)
    end
  end
end
