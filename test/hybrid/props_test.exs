defmodule PhoenixVapor.Hybrid.PropsTest do
  use ExUnit.Case, async: true

  alias PhoenixVapor.Hybrid.Props
  alias PhoenixVapor.Prop

  describe "build_envelope/3" do
    test "builds a full envelope by default" do
      envelope = Props.build_envelope(%{contacts: [1], page: 2}, ["contacts", "page"])

      assert envelope.full == true
      assert envelope.props == %{"contacts" => [1], "page" => 2}
    end

    test "builds a partial envelope from changed atom keys when enabled" do
      envelope =
        Props.build_envelope(
          %{contacts: [1], page: 2, __changed__: %{contacts: true}},
          ["contacts", "page"],
          partial: true
        )

      assert envelope.full == false
      assert envelope.props == %{"contacts" => [1]}
    end

    test "builds a partial envelope from changed string keys when enabled" do
      envelope =
        Props.build_envelope(
          %{contacts: [1], page: 2, __changed__: %{"page" => true}},
          ["contacts", "page"],
          partial: true
        )

      assert envelope.full == false
      assert envelope.props == %{"page" => 2}
    end

    test "keeps nil changed props in partial envelopes" do
      envelope =
        Props.build_envelope(
          %{contacts: nil, page: 2, __changed__: %{contacts: true}},
          ["contacts", "page"],
          partial: true
        )

      assert envelope.full == false
      assert Map.has_key?(envelope.props, "contacts")
      assert envelope.props["contacts"] == nil
    end

    test "falls back to a full envelope without LiveView change metadata" do
      envelope =
        Props.build_envelope(%{contacts: [1], page: 2}, ["contacts", "page"], partial: true)

      assert envelope.full == true
      assert envelope.props == %{"contacts" => [1], "page" => 2}
    end

    test "advanced props override regular assigns" do
      envelope =
        Props.build_envelope(
          %{countries: ["old"], __pv_props__: %{countries: ["US"]}},
          ["countries"]
        )

      assert envelope.props == %{"countries" => ["US"]}
    end

    test "always props are unwrapped" do
      envelope =
        Props.build_envelope(
          %{__pv_props__: %{countries: Prop.always(["US"])}},
          ["countries"]
        )

      assert envelope.props == %{"countries" => ["US"]}
    end

    test "optional props are omitted from full envelopes" do
      envelope =
        Props.build_envelope(
          %{__pv_props__: %{stats: Prop.optional(fn -> :expensive end)}},
          ["stats"]
        )

      assert envelope.props == %{}
    end

    test "preserved keys match defineProps keys by output name" do
      envelope =
        Props.build_envelope(
          %{__pv_props__: %{Prop.preserve_case(:user_id) => 1}},
          ["user_id"]
        )

      assert envelope.props == %{"user_id" => 1}
    end

    test "deferred props are omitted and listed by group" do
      envelope =
        Props.build_envelope(
          %{
            contacts: [1],
            __pv_props__: %{
              stats: Prop.defer(fn -> :stats end),
              permissions: Prop.defer(fn -> :permissions end, "auth")
            }
          },
          ["contacts", "stats", "permissions"]
        )

      assert envelope.props == %{"contacts" => [1]}
      assert envelope.deferredProps == %{"default" => ["stats"], "auth" => ["permissions"]}
    end

    test "resolve_deferred evaluates matching group and removes resolved props" do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          __pv_props__: %{
            stats: Prop.defer(fn -> 10 end),
            permissions: Prop.defer(fn -> ["read"] end, "auth")
          }
        }
      }

      socket = Props.resolve_deferred(socket, "default")

      assert socket.assigns.stats == 10
      refute Map.has_key?(socket.assigns.__pv_props__, :stats)
      assert %Prop.Defer{} = socket.assigns.__pv_props__.permissions
    end
  end
end
