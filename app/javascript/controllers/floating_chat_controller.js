import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "openIcon", "closeIcon", "frame"]

  toggle() {
    const isHidden = this.panelTarget.classList.contains("hidden")

    if (isHidden) {
      this.open()
    } else {
      this.close()
    }
  }

  open() {
    this.panelTarget.classList.remove("hidden")
    this.openIconTarget.classList.add("hidden")
    this.closeIconTarget.classList.remove("hidden")
  }

  close() {
    this.panelTarget.classList.add("hidden")
    this.openIconTarget.classList.remove("hidden")
    this.closeIconTarget.classList.add("hidden")
  }
}
