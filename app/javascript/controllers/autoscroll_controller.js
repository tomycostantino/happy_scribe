import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.scrollToBottom()
    this.observeMutations()
  }

  disconnect() {
    this.observer?.disconnect()
  }

  observeMutations() {
    this.observer = new MutationObserver(() => {
      if (this.isNearBottom()) {
        this.scrollToBottom()
      }
    })

    this.observer.observe(this.element, {
      childList: true,
      subtree: true,
      characterData: true
    })
  }

  isNearBottom() {
    const threshold = 100
    const position = this.element.scrollTop + this.element.clientHeight
    const height = this.element.scrollHeight
    return height - position < threshold
  }

  scrollToBottom() {
    this.element.scrollTop = this.element.scrollHeight
  }
}
