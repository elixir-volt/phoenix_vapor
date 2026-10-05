defmodule VaporDemo.E2E.ReplayRecorder do
  @moduledoc """
  Drives `replay_recorder.ts`, which stands in for a session replayer in the
  browser: starting and stopping a recording, and collecting the client
  state the hybrid components report.
  """

  import PhoenixTest.Playwright, only: [evaluate: 2, evaluate: 3]

  # The page gets plain JavaScript; OXC strips the types.
  @external_resource source = Path.join(__DIR__, "replay_recorder.ts")
  @script source |> File.read!() |> OXC.transform!("replay_recorder.ts")

  @doc "Loads the recorder into the page; it collects reports from then on."
  def install(conn), do: evaluate(conn, @script)

  @doc "Starts recording, with client-state settings such as `%{flush: 50}`, or `nil`."
  def start(conn, settings), do: call(conn, "start", [settings])

  def stop(conn), do: call(conn, "stop", [])

  @doc "Marks a recording as running, for components that mount later."
  def mark_recording(conn, settings), do: call(conn, "markRecording", [settings])

  @doc "Hides the page, as switching tabs does."
  def hide(conn), do: call(conn, "hide", [])

  @doc "Passes the reports so far, once a flush interval has passed, to `fun`."
  def reports(conn, fun), do: evaluate(conn, "replayRecorder.reports()", fun)

  defp call(conn, function, args),
    do:
      evaluate(conn, "replayRecorder.#{function}(#{Enum.map_join(args, ", ", &Jason.encode!/1)})")
end
