# Stands in for PhoenixReplay's `recording?/1`, true only in a test process
# that asks for it, so other tests don't see a recording.
unless Code.ensure_loaded?(PhoenixReplay) do
  defmodule PhoenixReplay do
    def recording?(_socket), do: Process.get(:phoenix_replay_recording, false)
  end
end

defmodule PhoenixVapor.Hybrid.RecordingTest do
  use ExUnit.Case, async: true

  alias Phoenix.LiveView.Socket
  alias PhoenixVapor.Hybrid.Recording

  defp socket(connected?) do
    %Socket{
      transport_pid: if(connected?, do: self()),
      private: %{lifecycle: %Phoenix.LiveView.Lifecycle{}, live_temp: %{}}
    }
  end

  test "asks the client for its refs, and keeps them in one assign, while recording" do
    Process.put(:phoenix_replay_recording, true)

    assert {:cont, socket} = Recording.on_mount(:default, %{}, %{}, socket(true))
    assert [["pv:record", %{}]] = socket.private.live_temp.push_events

    [hook] = socket.private.lifecycle.handle_event
    refs = %{"search" => "Ad"}
    assert {:halt, socket} = hook.function.("__pv_refs", refs, socket)
    assert socket.assigns.__pv_refs__ == refs

    assert {:cont, _socket} = hook.function.("save", %{}, socket)

    # A report too big to be UI state is dropped.
    huge = %{"search" => String.duplicate("x", 70_000)}
    assert {:halt, dropped} = hook.function.("__pv_refs", huge, socket)
    assert dropped.assigns.__pv_refs__ == refs
  end

  test "does nothing when the session isn't recorded" do
    Process.put(:phoenix_replay_recording, false)

    assert {:cont, socket} = Recording.on_mount(:default, %{}, %{}, socket(true))
    refute Map.has_key?(socket.private.live_temp, :push_events)
    assert socket.private.lifecycle.handle_event == []
  end

  test "does nothing on the disconnected render" do
    Process.put(:phoenix_replay_recording, true)

    assert {:cont, socket} = Recording.on_mount(:default, %{}, %{}, socket(false))
    assert socket.private.lifecycle.handle_event == []
  end
end
