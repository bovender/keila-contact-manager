import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Makes a table row navigate to a detail page on click, without hijacking
// clicks on interactive elements inside it (checkboxes, links, buttons).
export default class extends Controller {
  static values = { url: String }

  visit(event) {
    if (event.target.closest("a, button, input, label")) return

    Turbo.visit(this.urlValue)
  }
}
