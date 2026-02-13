import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["area", "input", "prompt"]

  connect() {
    this.areaTarget.addEventListener("click", () => this.inputTarget.click())
    this.areaTarget.addEventListener("dragover", (e) => this.dragOver(e))
    this.areaTarget.addEventListener("dragleave", () => this.dragLeave())
    this.areaTarget.addEventListener("drop", (e) => this.drop(e))
  }

  dragOver(e) {
    e.preventDefault()
    this.areaTarget.classList.add("border-blue-400", "bg-blue-50")
  }

  dragLeave() {
    this.areaTarget.classList.remove("border-blue-400", "bg-blue-50")
  }

  drop(e) {
    e.preventDefault()
    this.dragLeave()
    const files = e.dataTransfer.files
    if (files.length > 0) {
      this.inputTarget.files = files
      this.showFileName(files[0].name)
    }
  }

  picked() {
    const file = this.inputTarget.files[0]
    if (file) {
      this.showFileName(file.name)
    }
  }

  showFileName(name) {
    this.promptTarget.textContent = name
    this.promptTarget.classList.remove("text-gray-500")
    this.promptTarget.classList.add("text-blue-700", "font-medium")
  }
}
