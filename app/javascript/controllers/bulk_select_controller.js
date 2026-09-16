import { Controller } from "@hotwired/stimulus"

// Drives the contacts table's bulk-selection UI: a header checkbox that
// selects every row on the current page, and (when the filtered result set
// is bigger than one page) a banner offering to extend that selection to
// every contact matching the current filter, not just the ones visible.
export default class extends Controller {
  static targets = ["checkbox", "selectAllCheckbox", "selectAllMatchingField", "banner", "deleteButton"]
  static values = { total: Number }

  // Controllers connect asynchronously once their JS module has loaded,
  // which can trail a plain page visit by a perceptible amount (each
  // controller is its own module fetch). This flag gives tests something
  // concrete to wait on instead of racing ahead of it.
  connect() {
    this.element.dataset.bulkSelectReady = "true"
  }

  toggleAll() {
    const checked = this.selectAllCheckboxTarget.checked
    this.checkboxTargets.forEach((checkbox) => { checkbox.checked = checked })
    checked ? this.showBannerIfNeeded() : this.reset()
  }

  checkboxChanged() {
    const allChecked = this.checkboxTargets.length > 0 && this.checkboxTargets.every((checkbox) => checkbox.checked)
    this.selectAllCheckboxTarget.checked = allChecked
    allChecked ? this.showBannerIfNeeded() : this.reset()
  }

  selectAllMatching() {
    this.selectAllMatchingFieldTarget.value = "1"
    this.bannerTarget.hidden = true
    this.updateDeleteButton(this.totalValue)
  }

  showBannerIfNeeded() {
    this.bannerTarget.hidden = this.totalValue <= this.checkboxTargets.length
    this.updateDeleteButton(this.checkboxTargets.length)
  }

  reset() {
    this.selectAllMatchingFieldTarget.value = "0"
    this.bannerTarget.hidden = true
    this.updateDeleteButton(this.checkboxTargets.filter((checkbox) => checkbox.checked).length)
  }

  updateDeleteButton(count) {
    if (!this.hasDeleteButtonTarget) return

    this.deleteButtonTarget.dataset.turboConfirm =
      count > 0 ? `Delete ${count} contact${count === 1 ? "" : "s"}?` : "Delete all selected contacts?"
  }
}
