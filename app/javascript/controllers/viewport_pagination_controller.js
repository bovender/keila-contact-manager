import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Fits a table's page size to the browser window: measures how many rows
// fit below the table's top, and if the server rendered a different
// number, reloads the page once with that number as `per_page`, which the
// server remembers for this browser. Later visits then come out right
// straight away.
//
// It measures only when the page loads, never on a window resize, so the
// table doesn't change under the user's hands.
export default class extends Controller {
  static targets = [ "tbody", "pager" ]
  // Defaults, because a missing Number value would otherwise be 0.
  static values = {
    perPage: Number,
    minPerPage: { type: Number, default: 10 },
    maxPerPage: { type: Number, default: 200 }
  }

  async connect() {
    // Turbo shows cached snapshots as previews before the real page.
    if (document.documentElement.hasAttribute("data-turbo-preview")) return
    if (!this.hasTbodyTarget || this.rows.length === 0) return
    // Reloading would lose a flash message; the next visit corrects.
    if (document.querySelector("#notice, #alert")) return

    // Web fonts and lazily loaded frames above the table (like the sync
    // banner) can still change where and how tall the rows are.
    await Promise.all([ document.fonts.ready, ...this.loadingFrames.map(frameLoaded) ])
    if (this.element.isConnected) this.correct()
  }

  correct() {
    // The median row is the unit, so the occasional row with wrapped tags
    // doesn't make the page size jump around from page to page.
    const heights = this.rows.map((row) => row.getBoundingClientRect().height).sort((a, b) => a - b)
    const rowHeight = heights[Math.floor(heights.length / 2)]
    if (rowHeight <= 0) return

    const pagerHeight = this.hasPagerTarget ? this.pagerTarget.getBoundingClientRect().height + PAGER_MARGIN : ESTIMATED_PAGER_HEIGHT
    const available = document.documentElement.clientHeight - this.tbodyTarget.getBoundingClientRect().top - pagerHeight - BOTTOM_MARGIN
    const rowsThatFit = Math.floor(available / rowHeight)
    if (rowsThatFit < 1) return

    // Clamped like the server clamps, or a tiny window would keep asking
    // for fewer rows than the server ever sends, reloading on every visit.
    const perPage = Math.min(Math.max(rowsThatFit, this.minPerPageValue), this.maxPerPageValue)
    // Only a full page can tell that more rows would fit; the last page
    // of a list, or a short filtered one, can't.
    const full = this.rows.length >= this.perPageValue
    const shrink = this.rows.length > rowsThatFit && perPage < this.perPageValue
    const grow = full && perPage - this.perPageValue >= GROW_THRESHOLD
    if (!shrink && !grow) return

    const url = new URL(window.location.href)
    url.searchParams.set("per_page", perPage)
    // Page N means other contacts with another page size.
    url.searchParams.delete("page")
    Turbo.visit(url.toString(), { action: "replace" })
  }

  get rows() {
    return Array.from(this.tbodyTarget.rows)
  }

  get loadingFrames() {
    return Array.from(document.querySelectorAll("turbo-frame[src]:not([complete])"))
  }
}

// Resolves when the frame has loaded, or after a while if it doesn't
// (e.g. its request fails), so the table still gets measured.
function frameLoaded(frame) {
  return new Promise((resolve) => {
    frame.addEventListener("turbo:frame-load", resolve, { once: true })
    setTimeout(resolve, FRAME_TIMEOUT)
  })
}

// Growing by just a row or two isn't worth a reload.
const GROW_THRESHOLD = 3
// Room for the pager when there's none yet, but a smaller page size would
// bring it in; and the gap above it (mt-4) when there is one.
const ESTIMATED_PAGER_HEIGHT = 56
const PAGER_MARGIN = 16
// Breathing room below the pager.
const BOTTOM_MARGIN = 24
const FRAME_TIMEOUT = 3000
