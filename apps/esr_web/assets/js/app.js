// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/esr_web"
import topbar from "../vendor/topbar"

// Auto-scroll messages stream on new inserts AND preserve visual
// position on history prepend.
//
// Two cases this hook handles:
//   1. New chat message arrives (append at bottom) — scroll to bottom
//      iff the operator was already near it (don't yank from history).
//   2. Operator clicks "↑ Load older" (PR-5 prepend at top) — keep the
//      previously-topmost visible message at the same visual position
//      so the operator's eye doesn't jump. Without this, they'd either
//      stay glued to the bottom (case 1's rule) and never see the new
//      older messages, or jump to msg-1 and lose their place.
//
// Detection: beforeUpdate captures scrollHeight; updated compares.
// If height grew more than the bottom-room allowed, that growth came
// from a prepend — adjust scrollTop by the delta to compensate.
const ScrollOnUpdate = {
  _firstChildId() { return this.el.firstElementChild ? this.el.firstElementChild.id : null },
  mounted() {
    this.el.scrollTop = this.el.scrollHeight
    this._prevHeight = this.el.scrollHeight
    this._prevFirstId = this._firstChildId()
  },
  beforeUpdate() {
    this._prevHeight = this.el.scrollHeight
    this._prevScrollTop = this.el.scrollTop
    this._prevFirstId = this._firstChildId()
  },
  updated() {
    const el = this.el
    const grew = el.scrollHeight - (this._prevHeight || 0)
    const firstChanged = this._firstChildId() !== this._prevFirstId

    if (grew > 0 && firstChanged) {
      // Prepend (e.g. "↑ Load older"). Scroll up to reveal the newly
      // added older messages while keeping previously-visible content
      // still on screen as the user's anchor.
      el.scrollTop = grew
    } else {
      // Append (new chat message). Follow it down iff already near bottom.
      const wasNearBottom =
        (this._prevHeight || 0) - (this._prevScrollTop || 0) - el.clientHeight < 120
      if (wasNearBottom) el.scrollTop = el.scrollHeight
    }
    this._prevHeight = el.scrollHeight
    this._prevFirstId = this._firstChildId()
  }
}

// Phase 5 PR 4: Pty-Web xterm.js hook.
//
// Mounts an xterm.js Terminal inside `this.el`, subscribes to PubSub
// output via `handleEvent("pty_chunk", ...)`, and routes every
// keystroke through `pushEvent("pty_input", {bytes})` — which the LV
// then dispatches via Esr.Invocation.dispatch (CapBAC + audit + ...).
//
// CRITICAL: xterm input MUST go through pushEvent → LV → Invocation.dispatch.
// Never write to a PubSub topic directly from the JS side. The
// agents_pty_input_dispatch_test asserts the audit row count matches
// the input byte count — any future regression that bypasses dispatch
// will fail that test.
const PtyTerminal = {
  mounted() {
    const term = new window.Terminal({
      fontFamily: '"SF Mono", Menlo, Consolas, "DejaVu Sans Mono", monospace',
      fontSize: 13,
      theme: {background: "#1e1e1e", foreground: "#d4d4d4"},
      cursorBlink: true
    })
    const fitAddon = new window.FitAddon.FitAddon()
    term.loadAddon(fitAddon)
    term.open(this.el)
    fitAddon.fit()

    // Send window size to backend so PtyServer can :exec.winsz/3.
    this.pushEvent("pty_resize", {cols: term.cols, rows: term.rows})

    // Keystrokes → LV. NEVER PubSub directly (invariant #1).
    term.onData((data) => {
      this.pushEvent("pty_input", {bytes: data})
    })

    // Resize events also go to LV (which dispatches via Invocation).
    window.addEventListener("resize", () => {
      fitAddon.fit()
      this.pushEvent("pty_resize", {cols: term.cols, rows: term.rows})
    })

    // PubSub output chunks arrive via LV → pushEvent.
    this.handleEvent("pty_chunk", ({bytes}) => term.write(bytes))

    this.term = term
  },
  destroyed() {
    if (this.term) this.term.dispose()
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ScrollOnUpdate, PtyTerminal},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

