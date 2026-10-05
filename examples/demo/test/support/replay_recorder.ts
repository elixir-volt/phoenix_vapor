// Stands in for a session replayer such as PhoenixReplay: it starts and stops
// recording client state the way the replayer does, and collects the
// `phx_replay:state` reports the hybrid components send.
//
// `VaporDemo.E2E.ReplayRecorder` strips the types when it compiles, loads
// the result into the page, and calls it through `evaluate/3`, which hands
// what it returns to Elixir.

/** The client-state settings a replayer starts a recording with. */
type RecordingSettings = { flush?: number } | null

/** What a hybrid component reports: its key, and the state that changed. */
type StateReport = { key: string; changes: Record<string, unknown> }

const reports: StateReport[] = []

window.addEventListener("phx_replay:state", (event) => {
  reports.push((event as CustomEvent<StateReport>).detail)
})

const replayRecorder = {
  start(settings: RecordingSettings) {
    window.dispatchEvent(new CustomEvent("phx_replay:start", { detail: { state: settings } }))
  },

  stop() {
    window.dispatchEvent(new CustomEvent("phx_replay:stop"))
  },

  // Says a recording is already running, as the replayer does for
  // components that mount after it started.
  markRecording(settings: RecordingSettings) {
    document.documentElement.dataset.phxReplay = JSON.stringify({ state: settings })
  },

  // Hides the page, as switching tabs does.
  hide() {
    Object.defineProperty(document, "hidden", { value: true, configurable: true })
    document.dispatchEvent(new Event("visibilitychange"))
  },

  // The reports so far, once a flush interval has passed.
  async reports(wait = 150): Promise<StateReport[]> {
    await new Promise((resolve) => setTimeout(resolve, wait))
    return reports
  }
}

Object.assign(window, { replayRecorder })
