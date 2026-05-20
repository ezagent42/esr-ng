// Phase 8c PR-D — KPI count-up animation hook.
//
// Animates this.el.textContent from 0 → data-value over ~800ms using
// a requestAnimationFrame loop with an ease-out curve (t^0.8).
//
// Usage:
//   <span phx-hook="CountUp" data-value={@sessions} id="kpi-sessions">{@sessions}</span>
//
// `data-value` is the source of truth — the rendered text starts at the
// target (so SSR doesn't show "0" if JS fails to boot) and the hook
// resets to 0 on mount before animating. If the value changes (LV
// re-render with a new data-value), `updated()` re-runs the animation
// from the current displayed number to the new target — no jump.

const DURATION_MS = 800
const EASE_POWER  = 0.8  // ease-out (lower than 1 = faster start, slower end)

export const CountUp = {
  mounted() {
    const target = parseInt(this.el.dataset.value, 10) || 0
    this._animate(0, target)
  },

  updated() {
    const target = parseInt(this.el.dataset.value, 10) || 0
    const current = parseInt(this.el.textContent, 10) || 0
    if (current !== target) this._animate(current, target)
  },

  destroyed() {
    if (this._raf) cancelAnimationFrame(this._raf)
  },

  _animate(from, to) {
    if (this._raf) cancelAnimationFrame(this._raf)
    const start = performance.now()
    const delta = to - from

    const tick = (now) => {
      const t = Math.min(1, (now - start) / DURATION_MS)
      const eased = Math.pow(t, EASE_POWER)
      const value = Math.floor(from + delta * eased)
      this.el.textContent = value
      if (t < 1) {
        this._raf = requestAnimationFrame(tick)
      } else {
        this.el.textContent = to
        this._raf = null
      }
    }

    this._raf = requestAnimationFrame(tick)
  }
}
