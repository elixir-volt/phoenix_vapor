defmodule PhoenixVapor.Hybrid.ServerCodegenTest do
  use ExUnit.Case, async: true

  alias PhoenixVapor.Compiler.ScriptSetup

  alias PhoenixVapor.Hybrid.{Classifier, ServerCodegen}

  defp parse_and_classify(script, template) do
    setup = PhoenixVapor.Compiler.ScriptSetup.parse(script)
    classification = Classifier.classify(setup)

    split = Vize.split_template!(template)
    {split, classification, setup.props}
  end

  defp spec(split, client_props) do
    %{
      split: split,
      client_props: client_props,
      refs: [],
      values: %{},
      constant: [],
      computeds: [],
      component: nil
    }
  end

  defp render_to_html(rendered) do
    dynamic = rendered.dynamic.(false)

    rendered.static
    |> Enum.with_index()
    |> Enum.map(fn {s, i} ->
      case Enum.at(dynamic, i) do
        nil -> s
        %Phoenix.LiveView.Rendered{} = r -> s <> render_to_html(r)
        d -> s <> to_string(d)
      end
    end)
    |> IO.iodata_to_binary()
  end

  describe "build_rendered/6" do
    test "wraps content in data-pv div with props JSON" do
      {split, classification, _} =
        parse_and_classify(
          """
          import { ref } from "vue"
          defineProps(["count"])
          const search = ref("")
          """,
          "<p>{{ count }}</p>"
        )

      assigns = %{count: 42}

      rendered =
        ServerCodegen.build_rendered(spec(split, classification.client_props), assigns)

      html = render_to_html(rendered)
      assert html =~ "data-pv"
      assert html =~ "data-pv-props="
    end

    test "props JSON contains only client-consumed props" do
      {split, classification, _} =
        parse_and_classify(
          """
          import { ref, computed } from "vue"
          defineProps(["users", "serverOnly"])
          const search = ref("")
          const filtered = computed(() => users.filter(u => u.name.includes(search.value)))
          """,
          "<p>{{ filtered.length }} / {{ serverOnly }}</p>"
        )

      assigns = %{users: [%{name: "Alice"}], serverOnly: "secret"}

      rendered =
        ServerCodegen.build_rendered(spec(split, classification.client_props), assigns)

      html = render_to_html(rendered)
      assert html =~ "Alice"
      refute html =~ ~r/data-pv-props="[^"]*secret/
    end

    test "produces valid %Rendered{} struct" do
      {split, classification, _} =
        parse_and_classify(
          ~s|defineProps(["msg"])|,
          "<div>{{ msg }}</div>"
        )

      assigns = %{msg: "hello"}

      rendered =
        ServerCodegen.build_rendered(spec(split, classification.client_props), assigns)

      assert %Phoenix.LiveView.Rendered{} = rendered
      assert is_list(rendered.static)
      assert is_function(rendered.dynamic, 1)
      assert is_integer(rendered.fingerprint)
    end

    test "inner content renders all slots for first paint" do
      {split, classification, _} =
        parse_and_classify(
          """
          import { ref } from "vue"
          defineProps(["users"])
          const search = ref("")
          """,
          "<div><p>{{ search }}</p><p>{{ users.length }}</p></div>"
        )

      assigns = %{users: [1, 2, 3], search: ""}

      rendered =
        ServerCodegen.build_rendered(spec(split, classification.client_props), assigns)

      html = render_to_html(rendered)
      assert html =~ "3"
    end
  end

  describe "gen_handle_events/1" do
    test "generates handle_event for server actions" do
      classification =
        Classifier.classify(%ScriptSetup{
          refs: %{},
          computeds: %{},
          functions: %{
            "deleteUser" => ~s["use server"; users = users.filter(u => u.id !== id)],
            "clearSearch" => ~s[search.value = ""]
          },
          props: ["users"]
        })

      events = ServerCodegen.gen_handle_events(classification)

      assert length(events) == 1
      # Should register a @before_compile with the action names
      ast = hd(events)
      assert Macro.to_string(ast) =~ "deleteUser"
    end

    test "no events for client-only handlers" do
      classification =
        Classifier.classify(%ScriptSetup{
          refs: %{"search" => ~s("")},
          computeds: %{},
          functions: %{"clearSearch" => ~s[search.value = ""]},
          props: []
        })

      events = ServerCodegen.gen_handle_events(classification)
      assert events == []
    end
  end

  describe "gen_render/3" do
    test "generates a render/1 function definition" do
      {split, classification, _props} =
        parse_and_classify(
          ~s|defineProps(["msg"])|,
          "<div>{{ msg }}</div>"
        )

      {:__block__, _, definitions} = ServerCodegen.gen_render(split, classification)
      names = for {:def, _, [{name, _, _} | _]} <- definitions, do: name

      assert names == [:render, :replay_render]
    end
  end
end
