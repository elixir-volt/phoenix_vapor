defmodule PhoenixVapor.HybridTest do
  use ExUnit.Case, async: true

  defmodule SimpleLive do
    use Phoenix.LiveView
    use PhoenixVapor, file: "../fixtures/Hybrid.vue"
  end

  defmodule ContactsLive do
    use Phoenix.LiveView
    use PhoenixVapor, file: "../fixtures/HybridContacts.vue"
  end

  defmodule PartialContactsLive do
    use Phoenix.LiveView
    use PhoenixVapor, file: "../fixtures/HybridContacts.vue", partial_props: true
  end

  @contacts [
    %{id: 1, name: "Alice Chen", email: "alice@test.com"},
    %{id: 2, name: "Bob Smith", email: "bob@test.com"},
    %{id: 3, name: "Carol Davis", email: "carol@test.com"}
  ]

  defp render_to_html(rendered) do
    dynamic = rendered.dynamic.(false)

    rendered.static
    |> Enum.with_index()
    |> Enum.map(fn {s, i} ->
      case Enum.at(dynamic, i) do
        nil -> s
        %Phoenix.LiveView.Rendered{} = r -> s <> render_to_html(r)
        %Phoenix.LiveView.Comprehension{} = c -> s <> render_comprehension(c)
        d -> s <> to_string(d)
      end
    end)
    |> IO.iodata_to_binary()
  end

  defp render_comprehension(c) do
    c.entries
    |> Enum.map(fn {_, _, f} ->
      d = f.(%{}, false)

      c.static
      |> Enum.with_index()
      |> Enum.map(fn {s, i} ->
        case Enum.at(d, i) do
          nil -> s
          %Phoenix.LiveView.Rendered{} = r -> s <> render_to_html(r)
          v -> s <> to_string(v)
        end
      end)
      |> IO.iodata_to_binary()
    end)
    |> IO.iodata_to_binary()
  end

  defp extract_props_json(html) do
    case PhoenixVapor.Testing.hybrid_envelope(html) do
      %{"props" => props} -> props
      props -> props
    end
  end

  # ── Server Rendering ──

  describe "server render: HTML structure" do
    test "wrapper has id attribute" do
      html = ContactsLive.render(%{contacts: @contacts, title: "T"}) |> render_to_html()
      assert html =~ ~s(id="pv-HybridContacts")
    end

    test "wrapper has phx-hook attribute" do
      html = ContactsLive.render(%{contacts: @contacts, title: "T"}) |> render_to_html()
      assert html =~ ~s(phx-hook="PhoenixVaporHybrid")
    end

    test "wrapper has data-pv-client attribute" do
      html = ContactsLive.render(%{contacts: @contacts, title: "T"}) |> render_to_html()
      assert html =~ ~s(data-pv-client="HybridContacts")
    end

    test "wrapper has data-pv-props attribute with JSON" do
      html = ContactsLive.render(%{contacts: @contacts, title: "T"}) |> render_to_html()
      props = extract_props_json(html)
      assert is_map(props)
    end

    test "wrapper has structured prop envelope metadata" do
      html = ContactsLive.render(%{contacts: @contacts, title: "T"}) |> render_to_html()
      envelope = PhoenixVapor.Testing.hybrid_envelope(html)

      assert envelope["version"] == 1
      assert envelope["component"] == "HybridContacts"
      assert envelope["full"] == true
      assert is_binary(envelope["clientVersion"])
      assert html =~ ~s(data-pv-version="#{envelope["clientVersion"]}")
    end

    test "partial props opt-in emits partial envelopes when LiveView reports changes" do
      html =
        PartialContactsLive.render(%{
          contacts: @contacts,
          title: "T",
          __changed__: %{contacts: true}
        })
        |> render_to_html()

      envelope = PhoenixVapor.Testing.hybrid_envelope(html)

      assert envelope["full"] == false
      assert Map.keys(envelope["props"]) == ["contacts"]
    end
  end

  describe "server render: props serialization" do
    test "props JSON contains contacts array" do
      html = ContactsLive.render(%{contacts: @contacts, title: "T"}) |> render_to_html()
      props = extract_props_json(html)
      assert is_list(props["contacts"])
      assert length(props["contacts"]) == 3
    end

    test "props JSON contains contact fields" do
      html = ContactsLive.render(%{contacts: @contacts, title: "T"}) |> render_to_html()
      props = extract_props_json(html)
      first = hd(props["contacts"])
      assert first["name"] == "Alice Chen"
      assert first["email"] == "alice@test.com"
      assert first["id"] == 1
    end

    test "server-only props are excluded from JSON" do
      html = ContactsLive.render(%{contacts: @contacts, title: "T"}) |> render_to_html()
      props = extract_props_json(html)
      refute Map.has_key?(props, "title")
    end

    test "empty contacts produces empty array in props" do
      html = ContactsLive.render(%{contacts: [], title: "T"}) |> render_to_html()
      props = extract_props_json(html)
      assert props["contacts"] == []
    end
  end

  describe "server render: initial paint" do
    test "renders title for SEO" do
      html = ContactsLive.render(%{contacts: @contacts, title: "My Contacts"}) |> render_to_html()
      assert html =~ "My Contacts"
    end

    test "renders contact names for SEO" do
      html = ContactsLive.render(%{contacts: @contacts, title: "T"}) |> render_to_html()
      assert html =~ "Alice Chen"
      assert html =~ "Bob Smith"
      assert html =~ "Carol Davis"
    end

    test "renders contact emails" do
      html = ContactsLive.render(%{contacts: @contacts, title: "T"}) |> render_to_html()
      assert html =~ "alice@test.com"
      assert html =~ "bob@test.com"
    end

    test "renders contact count" do
      html = ContactsLive.render(%{contacts: @contacts, title: "T"}) |> render_to_html()
      assert html =~ "3 of 3 contacts"
    end

    test "renders filtered count with default search (empty)" do
      html = ContactsLive.render(%{contacts: @contacts, title: "T"}) |> render_to_html()
      assert html =~ "3 of 3"
    end

    test "renders v-for items as comprehension" do
      rendered = ContactsLive.render(%{contacts: @contacts, title: "T"})
      dynamic = rendered.dynamic.(false)

      has_comprehension =
        dynamic
        |> List.flatten()
        |> Enum.any?(fn
          %Phoenix.LiveView.Comprehension{} ->
            true

          %Phoenix.LiveView.Rendered{dynamic: d} ->
            d.(false)
            |> List.flatten()
            |> Enum.any?(&match?(%Phoenix.LiveView.Comprehension{}, &1))

          _ ->
            false
        end)

      assert has_comprehension
    end
  end

  describe "server render: %Rendered{} struct" do
    test "produces valid %Rendered{}" do
      rendered = ContactsLive.render(%{contacts: @contacts, title: "T"})
      assert %Phoenix.LiveView.Rendered{} = rendered
      assert is_list(rendered.static)
      assert is_function(rendered.dynamic, 1)
      assert is_integer(rendered.fingerprint)
    end

    test "fingerprint is stable for same template" do
      r1 = ContactsLive.render(%{contacts: @contacts, title: "A"})
      r2 = ContactsLive.render(%{contacts: @contacts, title: "B"})
      assert r1.fingerprint == r2.fingerprint
    end

    test "statics have N+1 elements for N dynamics" do
      rendered = ContactsLive.render(%{contacts: @contacts, title: "T"})
      dynamics = rendered.dynamic.(false)
      assert length(rendered.static) == length(dynamics) + 1
    end
  end

  # ── Classification ──

  describe "classification: const props = defineProps pattern" do
    test "contacts is a server prop" do
      c = ContactsLive.__hybrid_classification__()
      assert c.bindings["contacts"] == :server_prop
    end

    test "title is a server prop" do
      c = ContactsLive.__hybrid_classification__()
      assert c.bindings["title"] == :server_prop
    end

    test "search is a client ref" do
      c = ContactsLive.__hybrid_classification__()
      assert {:client_ref, _} = c.bindings["search"]
    end

    test "sortKey is a client ref" do
      c = ContactsLive.__hybrid_classification__()
      assert {:client_ref, _} = c.bindings["sortKey"]
    end

    test "selectedIds is a client ref" do
      c = ContactsLive.__hybrid_classification__()
      assert {:client_ref, _} = c.bindings["selectedIds"]
    end

    test "showDialog is a client ref" do
      c = ContactsLive.__hybrid_classification__()
      assert {:client_ref, _} = c.bindings["showDialog"]
    end

    test "filtered is a mixed computed (depends on contacts + search + sortKey)" do
      c = ContactsLive.__hybrid_classification__()
      assert {:mixed_computed, server_deps, client_deps} = c.bindings["filtered"]
      assert "contacts" in server_deps
      assert "search" in client_deps
    end

    test "selectedCount is a client computed" do
      c = ContactsLive.__hybrid_classification__()
      assert c.bindings["selectedCount"] == :client_computed
    end

    test "contacts is a client prop (used by mixed computed)" do
      c = ContactsLive.__hybrid_classification__()
      assert "contacts" in c.client_props
    end

    test "title is a server-only prop (not used by any client computed)" do
      c = ContactsLive.__hybrid_classification__()
      assert "title" in c.server_only_props
    end
  end

  describe "classification: handlers" do
    test "deleteContact is a server action (use server directive)" do
      c = ContactsLive.__hybrid_classification__()
      assert {:server_action, body} = c.handlers["deleteContact"]
      refute body =~ "use server"
    end

    test "deleteSelected is a server action (use server directive)" do
      c = ContactsLive.__hybrid_classification__()
      assert {:server_action, _} = c.handlers["deleteSelected"]
    end

    test "clearSearch is a client handler" do
      c = ContactsLive.__hybrid_classification__()
      assert c.handlers["clearSearch"] == :client_handler
    end

    test "toggleSelect is a client handler" do
      c = ContactsLive.__hybrid_classification__()
      assert c.handlers["toggleSelect"] == :client_handler
    end

    test "openDialog is a client handler" do
      c = ContactsLive.__hybrid_classification__()
      assert c.handlers["openDialog"] == :client_handler
    end

    test "closeDialog is a client handler" do
      c = ContactsLive.__hybrid_classification__()
      assert c.handlers["closeDialog"] == :client_handler
    end
  end

  # ── Client JS ──

  describe "client JS: validity" do
    test "generated JS is parseable" do
      js = ContactsLive.__hybrid_client_js__()
      assert {:ok, _} = OXC.parse(js, "output.js")
    end

    test "generated JS is non-trivial" do
      js = ContactsLive.__hybrid_client_js__()
      assert byte_size(js) > 1000
    end
  end

  describe "client JS: bridge exports" do
    test "exports __applyProps" do
      js = ContactsLive.__hybrid_client_js__()
      assert js =~ "export function __applyProps"
    end

    test "exports __setBridge" do
      js = ContactsLive.__hybrid_client_js__()
      assert js =~ "export function __setBridge"
    end

    test "exports __mount" do
      js = ContactsLive.__hybrid_client_js__()
      assert js =~ "export function __mount"
    end

    test "exports default component" do
      js = ContactsLive.__hybrid_client_js__()
      assert js =~ "export { __component as default }" or js =~ "export default"
    end
  end

  describe "client JS: server actions" do
    test "deleteContact has pushEvent call" do
      js = ContactsLive.__hybrid_client_js__()
      assert js =~ ~s(__bridge.pushEvent("deleteContact")
    end

    test "deleteSelected has pushEvent call" do
      js = ContactsLive.__hybrid_client_js__()
      assert js =~ ~s(__bridge.pushEvent("deleteSelected")
    end

    test "deleteContact sends id param" do
      js = ContactsLive.__hybrid_client_js__()
      assert js =~ ~s(pushEvent("deleteContact", { id: id })
    end

    test "clearSearch does NOT have pushEvent" do
      js = ContactsLive.__hybrid_client_js__()
      refute js =~ ~s(pushEvent("clearSearch")
    end

    test "toggleSelect does NOT have pushEvent" do
      js = ContactsLive.__hybrid_client_js__()
      refute js =~ ~s(pushEvent("toggleSelect")
    end

    test "openDialog does NOT have pushEvent" do
      js = ContactsLive.__hybrid_client_js__()
      refute js =~ ~s(pushEvent("openDialog")
    end
  end

  describe "client JS: Vue component structure" do
    test "has component props declaration" do
      js = ContactsLive.__hybrid_client_js__()
      assert js =~ ~s(props: ["contacts")
    end

    test "has setup function" do
      js = ContactsLive.__hybrid_client_js__()
      assert js =~ "setup(__props"
    end

    test "has client refs" do
      js = ContactsLive.__hybrid_client_js__()
      assert js =~ ~s|ref("")|
      assert js =~ ~s|ref("name")|
      assert js =~ "ref([])"
      assert js =~ "ref(false)"
    end

    test "has computed definitions" do
      js = ContactsLive.__hybrid_client_js__()
      assert js =~ "computed("
    end

    test "has client handler functions preserved" do
      js = ContactsLive.__hybrid_client_js__()
      assert js =~ "function clearSearch"
      assert js =~ "function toggleSelect"
      assert js =~ "function openDialog"
      assert js =~ "function closeDialog"
    end

    test "has render function with Vue elements" do
      js = ContactsLive.__hybrid_client_js__()
      assert js =~ "createElementVNode" or js =~ "openBlock"
    end
  end

  describe "client JS: client state keys" do
    test "__getClientState lists client refs" do
      js = ContactsLive.__hybrid_client_js__()
      assert js =~ "__getClientState"
      assert js =~ ~s("search")
      assert js =~ ~s("sortKey")
      assert js =~ ~s("selectedIds")
      assert js =~ ~s("showDialog")
    end
  end

  # ── handle_event ──

  describe "handle_event: server actions" do
    test "handle_event/3 is defined" do
      assert function_exported?(ContactsLive, :handle_event, 3)
    end

    test "fallback handler returns {:noreply, socket}" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{__changed__: %{}, flash: %{}, live_action: nil},
        private: %{assign_new: {%{}, []}}
      }

      assert {:noreply, ^socket} = ContactsLive.handle_event("deleteContact", %{}, socket)
    end
  end

  # ── Simple fixture (bare defineProps) ──

  describe "simple fixture: bare defineProps" do
    test "render/1 is defined" do
      assert function_exported?(SimpleLive, :render, 1)
    end

    test "classification detects users as server prop" do
      c = SimpleLive.__hybrid_classification__()
      assert c.bindings["users"] == :server_prop
    end

    test "generates valid client JS" do
      js = SimpleLive.__hybrid_client_js__()
      assert {:ok, _} = OXC.parse(js, "output.js")
    end
  end
end
