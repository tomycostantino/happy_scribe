import { Controller } from "@hotwired/stimulus"
import { marked } from "marked"

// Renders markdown content in chat messages.
//
// During streaming, raw text chunks are appended to the element by Turbo Streams.
// The controller intercepts these via MutationObserver, accumulates raw markdown,
// and re-renders the HTML. On connect (page load or after broadcast_finished),
// it renders whatever content is already present.
export default class extends Controller {
  connect() {
    this.configureMarked()
    this.streaming = false
    this.rawContent = this.element.textContent || ""
    this.render()
    this.observeMutations()
  }

  disconnect() {
    this.observer?.disconnect()
    clearTimeout(this.renderTimeout)
  }

  configureMarked() {
    marked.setOptions({
      breaks: true,
      gfm: true
    })
  }

  observeMutations() {
    this.observer = new MutationObserver((mutations) => {
      let hasNewContent = false

      for (const mutation of mutations) {
        if (mutation.type === "childList" && mutation.addedNodes.length > 0) {
          for (const node of mutation.addedNodes) {
            // Skip nodes we inserted ourselves during render
            if (node._markdownRendered) continue
            this.rawContent += node.textContent || ""
            node.remove()
            hasNewContent = true
          }
        }
      }

      if (hasNewContent) {
        this.streaming = true
        this.debouncedRender()
      }
    })

    this.observer.observe(this.element, { childList: true })
  }

  // Debounce renders during streaming to avoid excessive re-parsing
  debouncedRender() {
    clearTimeout(this.renderTimeout)
    this.renderTimeout = setTimeout(() => this.render(), 50)
  }

  render() {
    if (!this.rawContent.trim()) return

    // Pause observer while we replace innerHTML to avoid infinite loops
    this.observer?.disconnect()

    const html = marked.parse(this.rawContent)
    this.element.innerHTML = html

    // Mark all child nodes so the observer can distinguish them from Turbo Stream appends
    for (const child of this.element.childNodes) {
      child._markdownRendered = true
    }

    // Resume observing
    if (this.observer) {
      this.observer.observe(this.element, { childList: true })
    }
  }
}
