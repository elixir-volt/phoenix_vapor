defmodule PhoenixVapor.Hybrid.ServerCodegenTest do
  use ExUnit.Case, async: true

  alias PhoenixVapor.Hybrid.{Classifier, ServerCodegen}

  defp parse_and_classify(script, template) do
    {refs, computeds, functions, function_bodies, props} =
      PhoenixVapor.ScriptSetup.parse(script)

    classification = Classifier.classify(refs, computeds, functions, function_bodies, props)
    split = Vize.vapor_split!(template)
    {split, classification, props}
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

  describe "classify_slots/2" do
    test "server-only slot" do
      {split, classification, _} =
        parse_and_classify(
          ~s|defineProps(["title"])|,
          "<h1>{{ title }}</h1>"
        )

      owners = ServerCodegen.classify_slots(split.slots, classification)
      assert owners == [:server]
    end

    test "client-only slot" do
      {split, classification, _} =
        parse_and_classify(
          """
          import { ref } from "vue"
          defineProps(["users"])
          const search = ref("")
          """,
          "<input :value=\"search\" />"
        )

      owners = ServerCodegen.classify_slots(split.slots, classification)
      assert owners == [:client]
    end

    test "mixed computed slot is client-owned" do
      {split, classification, _} =
        parse_and_classify(
          """
          import { ref, computed } from "vue"
          defineProps(["users"])
          const search = ref("")
          const filtered = computed(() => users.filter(u => u.name.includes(search.value)))
          """,
          "<p>{{ filtered.length }}</p>"
        )

      owners = ServerCodegen.classify_slots(split.slots, classification)
      assert owners == [:client]
    end

    test "mixed template with server and client slots" do
      {split, classification, _} =
        parse_and_classify(
          """
          import { ref, computed } from "vue"
          defineProps(["users", "title"])
          const search = ref("")
          const filtered = computed(() => users.filter(u => u.name.includes(search.value)))
          """,
          """
          <div>
            <h1>{{ title }}</h1>
            <input :value="search" />
            <p>{{ filtered.length }}</p>
          </div>
          """
        )

      owners = ServerCodegen.classify_slots(split.slots, classification)
      # title is server-only, search is client, filtered.length is client
      assert :server in owners
      assert :client in owners
    end
  end

  describe "build_rendered/4" do
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
      slot_owners = ServerCodegen.classify_slots(split.slots, classification)

      rendered =
        ServerCodegen.build_rendered(split, assigns, classification.client_props, slot_owners)

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
      slot_owners = ServerCodegen.classify_slots(split.slots, classification)

      rendered =
        ServerCodegen.build_rendered(split, assigns, classification.client_props, slot_owners)

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
      slot_owners = ServerCodegen.classify_slots(split.slots, classification)

      rendered =
        ServerCodegen.build_rendered(split, assigns, classification.client_props, slot_owners)

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
      slot_owners = ServerCodegen.classify_slots(split.slots, classification)

      rendered =
        ServerCodegen.build_rendered(split, assigns, classification.client_props, slot_owners)

      html = render_to_html(rendered)
      assert html =~ "3"
    end
  end

  describe "gen_handle_events/1" do
    test "generates handle_event for server actions" do
      classification =
        Classifier.classify(
          %{},
          %{},
          ["deleteUser", "clearSearch"],
          %{
            "deleteUser" => ~s["use server"; users = users.filter(u => u.id !== id)],
            "clearSearch" => ~s[search.value = ""]
          },
          ["users"]
        )

      events = ServerCodegen.gen_handle_events(classification)

      assert length(events) == 1

      [{:def, _, [{:handle_event, _, [event_name, _, _]}, _]}] = events
      assert event_name == "deleteUser"
    end

    test "no events for client-only handlers" do
      classification =
        Classifier.classify(
          %{"search" => ~s("")},
          %{},
          ["clearSearch"],
          %{"clearSearch" => ~s[search.value = ""]},
          []
        )

      events = ServerCodegen.gen_handle_events(classification)
      assert events == []
    end
  end

  describe "gen_render/3" do
    test "generates a render/1 function definition" do
      {split, classification, props} =
        parse_and_classify(
          ~s|defineProps(["msg"])|,
          "<div>{{ msg }}</div>"
        )

      ast = ServerCodegen.gen_render(split, classification, props)
      assert {:def, _, [{:render, _, _}, _]} = ast
    end
  end
end
