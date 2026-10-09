import "phoenix_html"
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import topbar from "../vendor/topbar"
import { patchLiveSocket } from "phoenix_vapor"
import { getHybridHooks } from "phoenix_vapor/hybrid"
import { replayMetadata, replayParams, replayRecorder } from "phoenix_replay"
import { installShell } from "./shell"

// The browser halves of the hybrid components, which PhoenixVapor generates
// while compiling.
import * as Board from "./hybrid/Board.hybrid.js"
import * as Issue from "./hybrid/Issue.hybrid.js"

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
  hooks: getHybridHooks({ Board, Issue })
})

// The end-to-end tests count reactive patches; `data-vapor-debug` on the
// body, set in the test environment, turns the counter on.
patchLiveSocket(liveSocket, { debug: document.body.hasAttribute("data-vapor-debug") })

topbar.config({ barColors: { 0: "#6e7bff" }, shadowColor: "rgba(0, 0, 0, .3)" })
window.addEventListener("phx:page-loading-start", () => topbar.show(300))
window.addEventListener("phx:page-loading-stop", () => topbar.hide())

installShell()
liveSocket.connect()
// Records what only the browser has: form input, and the hybrid components'
// client state, which they report themselves.
replayRecorder(liveSocket)
window.liveSocket = liveSocket
