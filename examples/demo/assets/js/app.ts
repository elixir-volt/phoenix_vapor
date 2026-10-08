import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import topbar from "../vendor/topbar"
import { patchLiveSocket } from "phoenix_vapor"
import { getHybridHooks } from "phoenix_vapor/hybrid"
import { replayMetadata, replayParams, replayRecorder } from "phoenix_replay"

// The browser halves of the hybrid components, which PhoenixVapor generates
// while compiling.
import * as Contacts from "./hybrid/Contacts.hybrid.js"
import * as ProjectSettings from "./hybrid/ProjectSettings.hybrid.js"
import * as Tally from "./hybrid/Tally.hybrid.js"

declare global {
  interface Window {
    liveSocket: InstanceType<typeof LiveSocket>
  }
}

const csrfToken = document.querySelector<HTMLMetaElement>("meta[name='csrf-token']")?.content

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  // The viewport, user agent and tab, for session replay.
  params: () => ({ _csrf_token: csrfToken, ...replayParams() }),
  metadata: replayMetadata,
  hooks: getHybridHooks({ Contacts, ProjectSettings, Tally })
})

// The end-to-end tests count reactive patches; `data-vapor-debug` on the
// body, set in the test environment, turns the counter on.
patchLiveSocket(liveSocket, { debug: document.body.hasAttribute("data-vapor-debug") })

topbar.config({ barColors: { 0: "#3f3f46" }, shadowColor: "rgba(0, 0, 0, .3)" })
window.addEventListener("phx:page-loading-start", () => topbar.show(300))
window.addEventListener("phx:page-loading-stop", () => topbar.hide())

liveSocket.connect()
// Records what only the browser has: form input, and the hybrid components'
// client state, which they report themselves.
replayRecorder(liveSocket)
window.liveSocket = liveSocket
