import { Controller } from "@hotwired/stimulus"

// A flash message floating over the page: goes away when clicked, or by
// itself after `timeout` milliseconds when it has one.
export default class extends Controller {
  static values = { timeout: Number }

  connect() {
    if (this.timeoutValue > 0) this.timer = setTimeout(() => this.dismiss(), this.timeoutValue)
    // Or it would show up again when going back to this page.
    this.dismissBeforeCache = () => this.dismiss()
    document.addEventListener("turbo:before-cache", this.dismissBeforeCache)
  }

  disconnect() {
    clearTimeout(this.timer)
    document.removeEventListener("turbo:before-cache", this.dismissBeforeCache)
  }

  dismiss() {
    this.element.remove()
  }
}
