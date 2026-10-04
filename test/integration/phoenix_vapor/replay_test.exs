defmodule PhoenixVapor.Integration.ReplayTest do
  # A session replayer, such as PhoenixReplay, renders a recorded view with the
  # assigns recorded at each step: no mount/3 and no events, only render/1 with
  # each step's assigns. These render every mode that way.
  use ExUnit.Case, async: true

  alias PhoenixVapor.Fixtures

  defmodule SigilLive do
    use Phoenix.LiveView
    use PhoenixVapor

    def render(assigns) do
      ~VUE"""
      <p>Count: {{ count }}</p>
      """
    end
  end

  defmodule ServerOnlyLive do
    use Phoenix.LiveView
    use PhoenixVapor, file: Fixtures.path("ServerOnlyProps.vue")
  end

  defmodule ReactiveLive do
    use Phoenix.LiveView
    use PhoenixVapor, file: Fixtures.path("Counter.vue"), runtime: :reactive
  end

  # The full runtime's render/1 reads only the HTML it recorded; compiling it
  # doesn't load the bundle.
  defmodule FullLive do
    use Phoenix.LiveView

    use PhoenixVapor,
      file: Fixtures.path("Probe.vue"),
      runtime: :full,
      bundle: "priv/js/reka-dialog.js",
      globals: %{"reka-ui" => "RekaDialog"}
  end

  defmodule HybridLive do
    use Phoenix.LiveView
    use PhoenixVapor, file: Fixtures.path("Hybrid.vue"), client_output: nil
  end

  defp html(rendered), do: rendered |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary()

  # Each step's recorded assigns, as the replayer assigns them.
  defp replay(render, steps), do: Enum.map(steps, &html(render.(Map.put(&1, :__changed__, nil))))

  test "server templates follow the recorded assigns" do
    assert replay(&SigilLive.render/1, [%{count: 0}, %{count: 1}, %{count: 2}]) ==
             ["<p>Count: 0</p>", "<p>Count: 1</p>", "<p>Count: 2</p>"]

    [first, second] = replay(&ServerOnlyLive.render/1, [%{items: ["a"]}, %{items: ["a", "b"]}])
    assert first =~ "<li>a</li>" and not (first =~ "<li>b</li>")
    assert second =~ "<li>b</li>"
  end

  test "reactive templates follow the recorded state, without their runtime" do
    [zero, one] =
      replay(&ReactiveLive.render/1, [%{count: 0, doubled: 0}, %{count: 1, doubled: 2}])

    assert zero =~ "0" and one =~ "2"
    refute zero == one
  end

  test "the full runtime replays its recorded HTML" do
    [closed, open] =
      replay(&FullLive.render/1, [
        %{__vue_html__: "<p>closed</p>"},
        %{__vue_html__: "<p>open</p>"}
      ])

    assert closed =~ "<p>closed</p>" and open =~ "<p>open</p>"
  end

  describe "hybrid" do
    @users [%{"id" => 1, "name" => "Ada"}, %{"id" => 2, "name" => "Bob"}]

    test "follows the recorded props, with the refs' initial values" do
      [both, one] =
        replay(&HybridLive.replay_render/1, [
          %{title: "Team", users: @users},
          %{title: "Team", users: tl(@users)}
        ])

      assert both =~ "<p>2 results</p>"
      assert one =~ "<p>1 results</p>"
    end

    test "follows the refs the client reported while recording" do
      [initial, searched] =
        replay(&HybridLive.replay_render/1, [
          %{title: "Team", users: @users},
          %{title: "Team", users: @users, __pv_refs__: %{"search" => "Ad"}}
        ])

      assert initial =~ "<p>2 results</p>"
      assert searched =~ ~s(value="Ad")
      assert searched =~ "<p>1 results</p>"
    end

    test "renders without the client hook, which a replay doesn't run" do
      [replayed] = replay(&HybridLive.replay_render/1, [%{title: "Team", users: @users}])
      [live] = replay(&HybridLive.render/1, [%{title: "Team", users: @users}])

      refute replayed =~ "phx-hook"
      refute replayed =~ ~s(phx-update="ignore")
      assert live =~ ~s(phx-hook="PhoenixVaporHybrid")
    end

    test "ignores reported names that aren't refs" do
      [rendered] =
        replay(&HybridLive.replay_render/1, [
          %{title: "Team", users: @users, __pv_refs__: %{"title" => "Hijacked", "search" => ""}}
        ])

      assert rendered =~ "<h1>Team</h1>"
    end
  end
end
