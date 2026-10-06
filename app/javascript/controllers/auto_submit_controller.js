import { Controller } from "@hotwired/stimulus"

// Submits its form as soon as it appears, e.g. to go straight on to single
// sign-on instead of showing a sign-in page with just one button on it.
export default class extends Controller {
  connect() {
    // Turbo shows cached snapshots as previews before the real page
    // arrives; submitting from those would send the form twice.
    if (document.documentElement.hasAttribute("data-turbo-preview")) return

    this.element.requestSubmit()
  }
}
