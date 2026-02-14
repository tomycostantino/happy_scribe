import { Controller } from "@hotwired/stimulus"
import { marked } from "marked"

// Renders markdown content in chat messages.
//
// During streaming, the server replaces the entire content div via Turbo Streams.
// Each replace triggers Stimulus disconnect/connect lifecycle, and connect()
// renders the current raw text as markdown. No MutationObserver needed.
export default class extends Controller {
  static SYSTEM_REMINDER_PATTERN = /<system-reminder>[\s\S]*?<\/system-reminder>/g

  connect() {
    this.configureMarked()
    this.render()
  }

  configureMarked() {
    marked.setOptions({
      breaks: true,
      gfm: true
    })
  }

  render() {
    const rawContent = this.stripInternalTags(this.element.textContent || "")
    if (!rawContent.trim()) return

    const html = marked.parse(rawContent)
    this.element.innerHTML = html
  }

  stripInternalTags(text) {
    return text.replace(this.constructor.SYSTEM_REMINDER_PATTERN, "")
  }
}
