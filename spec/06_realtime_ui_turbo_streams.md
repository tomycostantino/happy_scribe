# Spec 6: Real-time UI with Turbo Streams

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build all views, layouts, and Turbo Stream wiring so the user sees real-time progress updates as meetings are processed through the pipeline.

**Architecture:** Standard Rails views with Tailwind CSS. Turbo Streams broadcast partial updates from background jobs. Turbo Frames isolate interactive regions (action item toggles, follow-up email form). Stimulus controllers for file upload UX and action item toggling.

**Tech Stack:** Hotwire (Turbo + Stimulus), Tailwind CSS (already installed), ERB views.

**Dependencies:** Spec 1 (models), Spec 3 (controller), Spec 4 (AI jobs broadcast here).

---

## View Architecture

```
layouts/
  application.html.erb        — Main layout with nav, flash messages, Turbo Stream connection

meetings/
  index.html.erb              — List of meetings with live-updating status badges
  show.html.erb               — Meeting detail: status, transcript, summary, action items
  new.html.erb                — Upload form
  _form.html.erb              — File upload form partial
  _meeting.html.erb           — Single meeting row for index (Turbo Stream target)
  _status.html.erb            — Status badge partial (Turbo Stream target)
  _transcript.html.erb        — Transcript display partial (Turbo Stream target)
  _summary.html.erb           — Summary display partial (Turbo Stream target)
  _action_items.html.erb      — Action items list partial (Turbo Stream target)
```

## Turbo Stream Targets

Each broadcast from a job targets a specific DOM element:

| Target ID | Partial | Broadcast When |
|-----------|---------|----------------|
| `meeting_{id}_status` | `meetings/status` | Every status change |
| `meeting_{id}_summary` | `meetings/summary` | Summary created |
| `meeting_{id}_action_items` | `meetings/action_items` | Action items created |
| `meeting_{id}_transcript` | `meetings/transcript` | Transcript completed |
| `meeting_{id}` | `meetings/meeting` | Index row update |

---

### Task 1: Application Layout

**Files:**
- Modify: `app/views/layouts/application.html.erb`

**Step 1: Update the layout**

```erb
<%# app/views/layouts/application.html.erb %>
<!DOCTYPE html>
<html class="h-full bg-gray-50">
  <head>
    <title><%= content_for(:title) || "Happy Scribe" %></title>
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <%= csrf_meta_tags %>
    <%= csp_meta_tag %>

    <%= yield :head %>
    <link rel="icon" href="/icon.png" type="image/png">
    <link rel="icon" href="/icon.svg" type="image/svg+xml">
    <link rel="apple-touch-icon" href="/icon.png">

    <%= stylesheet_link_tag "tailwind", "inter-font", "data-turbo-track": "reload" %>
    <%= stylesheet_link_tag "application", "data-turbo-track": "reload" %>
    <%= javascript_importmap_tags %>
  </head>

  <body class="h-full">
    <div class="min-h-full">
      <% if authenticated? %>
        <nav class="bg-white shadow-sm">
          <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
            <div class="flex h-16 justify-between">
              <div class="flex">
                <%= link_to "Happy Scribe", meetings_path, class: "flex items-center text-xl font-bold text-indigo-600" %>
              </div>
              <div class="flex items-center gap-4">
                <span class="text-sm text-gray-500"><%= Current.user&.email_address %></span>
                <%= button_to "Sign out", session_path, method: :delete, class: "text-sm text-gray-500 hover:text-gray-700" %>
              </div>
            </div>
          </div>
        </nav>
      <% end %>

      <main class="mx-auto max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
        <% if notice.present? %>
          <div class="mb-4 rounded-md bg-green-50 p-4">
            <p class="text-sm text-green-700"><%= notice %></p>
          </div>
        <% end %>

        <% if alert.present? %>
          <div class="mb-4 rounded-md bg-red-50 p-4">
            <p class="text-sm text-red-700"><%= alert %></p>
          </div>
        <% end %>

        <%= yield %>
      </main>
    </div>
  </body>
</html>
```

**Step 2: Add `authenticated?` helper to ApplicationController**

```ruby
# app/controllers/application_controller.rb — add helper method
helper_method :authenticated?

def authenticated?
  Current.session.present?
end
```

**Step 3: Commit**

```bash
git add -A && git commit -m "feat: update application layout with nav and Tailwind styling"
```

---

### Task 2: Meetings Index View

**Files:**
- Create: `app/views/meetings/index.html.erb`
- Create: `app/views/meetings/_meeting.html.erb`
- Create: `app/views/meetings/_status.html.erb`

**Step 1: Create the index view**

```erb
<%# app/views/meetings/index.html.erb %>
<div class="flex items-center justify-between mb-8">
  <h1 class="text-2xl font-bold text-gray-900">Meetings</h1>
  <%= link_to "Upload Meeting", new_meeting_path,
    class: "rounded-md bg-indigo-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500" %>
</div>

<% if @meetings.any? %>
  <div class="bg-white shadow-sm rounded-lg divide-y divide-gray-200" id="meetings">
    <% @meetings.each do |meeting| %>
      <%= render meeting %>
    <% end %>
  </div>
<% else %>
  <div class="text-center py-12">
    <h3 class="text-sm font-semibold text-gray-900">No meetings yet</h3>
    <p class="mt-1 text-sm text-gray-500">Get started by uploading a meeting recording.</p>
    <div class="mt-6">
      <%= link_to "Upload Meeting", new_meeting_path,
        class: "rounded-md bg-indigo-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500" %>
    </div>
  </div>
<% end %>

<%# Subscribe to Turbo Stream updates for all displayed meetings %>
<% @meetings.each do |meeting| %>
  <%= turbo_stream_from meeting %>
<% end %>
```

**Step 2: Create the meeting partial (index row)**

```erb
<%# app/views/meetings/_meeting.html.erb %>
<%= turbo_frame_tag dom_id(meeting) do %>
  <div class="px-6 py-4 flex items-center justify-between" id="<%= dom_id(meeting) %>">
    <div class="flex-1 min-w-0">
      <%= link_to meeting_path(meeting), class: "block hover:bg-gray-50 -m-2 p-2 rounded" do %>
        <p class="text-sm font-semibold text-gray-900 truncate"><%= meeting.title %></p>
        <p class="text-sm text-gray-500">
          <%= meeting.created_at.strftime("%b %d, %Y at %I:%M %p") %>
          <span class="mx-1">&middot;</span>
          <%= meeting.language %>
        </p>
      <% end %>
    </div>
    <div class="ml-4 flex-shrink-0" id="meeting_<%= meeting.id %>_status">
      <%= render "meetings/status", meeting: meeting %>
    </div>
  </div>
<% end %>
```

**Step 3: Create the status badge partial**

```erb
<%# app/views/meetings/_status.html.erb %>
<% case meeting.status %>
<% when "uploading" %>
  <span class="inline-flex items-center rounded-full bg-yellow-100 px-2.5 py-0.5 text-xs font-medium text-yellow-800">
    <svg class="mr-1 h-3 w-3 animate-spin" fill="none" viewBox="0 0 24 24">
      <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
      <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"></path>
    </svg>
    Uploading
  </span>
<% when "transcribing" %>
  <span class="inline-flex items-center rounded-full bg-blue-100 px-2.5 py-0.5 text-xs font-medium text-blue-800">
    <svg class="mr-1 h-3 w-3 animate-spin" fill="none" viewBox="0 0 24 24">
      <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
      <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"></path>
    </svg>
    Transcribing
  </span>
<% when "transcribed" %>
  <span class="inline-flex items-center rounded-full bg-blue-100 px-2.5 py-0.5 text-xs font-medium text-blue-800">
    Transcribed
  </span>
<% when "processing" %>
  <span class="inline-flex items-center rounded-full bg-purple-100 px-2.5 py-0.5 text-xs font-medium text-purple-800">
    <svg class="mr-1 h-3 w-3 animate-spin" fill="none" viewBox="0 0 24 24">
      <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
      <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"></path>
    </svg>
    Processing AI
  </span>
<% when "completed" %>
  <span class="inline-flex items-center rounded-full bg-green-100 px-2.5 py-0.5 text-xs font-medium text-green-800">
    Completed
  </span>
<% when "failed" %>
  <span class="inline-flex items-center rounded-full bg-red-100 px-2.5 py-0.5 text-xs font-medium text-red-800">
    Failed
  </span>
<% end %>
```

**Step 4: Commit**

```bash
git add -A && git commit -m "feat: add meetings index view with live status badges"
```

---

### Task 3: Meeting Show View

**Files:**
- Create: `app/views/meetings/show.html.erb`
- Create: `app/views/meetings/_transcript.html.erb`
- Create: `app/views/meetings/_summary.html.erb`
- Create: `app/views/meetings/_action_items.html.erb`

**Step 1: Create the show view**

```erb
<%# app/views/meetings/show.html.erb %>
<%= turbo_stream_from @meeting %>

<div class="mb-6">
  <%= link_to "&larr; Back to meetings".html_safe, meetings_path, class: "text-sm text-indigo-600 hover:text-indigo-500" %>
</div>

<div class="bg-white shadow-sm rounded-lg overflow-hidden">
  <%# Header %>
  <div class="px-6 py-5 border-b border-gray-200">
    <div class="flex items-center justify-between">
      <div>
        <h1 class="text-xl font-bold text-gray-900"><%= @meeting.title %></h1>
        <p class="mt-1 text-sm text-gray-500">
          <%= @meeting.created_at.strftime("%B %d, %Y at %I:%M %p") %>
          <span class="mx-1">&middot;</span>
          <%= @meeting.language %>
          <% if @meeting.transcript&.audio_length_seconds %>
            <span class="mx-1">&middot;</span>
            <%= (@meeting.transcript.audio_length_seconds / 60.0).ceil %> min
          <% end %>
        </p>
      </div>
      <div id="meeting_<%= @meeting.id %>_status">
        <%= render "meetings/status", meeting: @meeting %>
      </div>
    </div>
  </div>

  <%# Summary section %>
  <div class="px-6 py-5 border-b border-gray-200" id="meeting_<%= @meeting.id %>_summary">
    <%= render "meetings/summary", summary: @meeting.summary %>
  </div>

  <%# Action Items section %>
  <div class="px-6 py-5 border-b border-gray-200" id="meeting_<%= @meeting.id %>_action_items">
    <%= render "meetings/action_items", action_items: @meeting.action_items %>
  </div>

  <%# Follow-up Email section (only when completed) %>
  <% if @meeting.completed? %>
    <div class="px-6 py-5 border-b border-gray-200">
      <%= turbo_frame_tag "follow_up_email" do %>
        <%= link_to "Send Follow-up Email",
          new_meeting_follow_up_email_path(@meeting),
          class: "rounded-md bg-indigo-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500",
          data: { turbo_frame: "follow_up_email" } %>
      <% end %>
    </div>
  <% end %>

  <%# Transcript section %>
  <div class="px-6 py-5" id="meeting_<%= @meeting.id %>_transcript">
    <%= render "meetings/transcript", transcript: @meeting.transcript %>
  </div>
</div>

<%# Delete meeting %>
<div class="mt-6 flex justify-end">
  <%= button_to "Delete Meeting", meeting_path(@meeting),
    method: :delete,
    class: "text-sm text-red-600 hover:text-red-500",
    data: { turbo_confirm: "Are you sure you want to delete this meeting?" } %>
</div>
```

**Step 2: Create the transcript partial**

```erb
<%# app/views/meetings/_transcript.html.erb %>
<% if transcript&.completed? && transcript.transcript_segments.any? %>
  <h2 class="text-lg font-semibold text-gray-900 mb-4">Transcript</h2>
  <div class="space-y-4 max-h-96 overflow-y-auto">
    <% transcript.transcript_segments.order(:position).each do |segment| %>
      <div class="flex gap-3">
        <div class="flex-shrink-0">
          <span class="inline-flex items-center rounded-full bg-gray-100 px-2.5 py-0.5 text-xs font-medium text-gray-800">
            <%= segment.speaker %>
          </span>
        </div>
        <div class="flex-1">
          <p class="text-sm text-gray-700"><%= segment.content %></p>
          <% if segment.start_time %>
            <p class="text-xs text-gray-400 mt-1">
              <%= Time.at(segment.start_time).utc.strftime("%H:%M:%S") %>
            </p>
          <% end %>
        </div>
      </div>
    <% end %>
  </div>
<% elsif transcript&.processing? || transcript&.pending? %>
  <h2 class="text-lg font-semibold text-gray-900 mb-4">Transcript</h2>
  <div class="flex items-center gap-2 text-sm text-gray-500">
    <svg class="h-4 w-4 animate-spin" fill="none" viewBox="0 0 24 24">
      <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
      <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"></path>
    </svg>
    Transcription in progress...
  </div>
<% elsif transcript&.failed? %>
  <h2 class="text-lg font-semibold text-gray-900 mb-4">Transcript</h2>
  <p class="text-sm text-red-600">Transcription failed. Please try uploading again.</p>
<% end %>
```

**Step 3: Create the summary partial**

```erb
<%# app/views/meetings/_summary.html.erb %>
<% if summary.present? %>
  <h2 class="text-lg font-semibold text-gray-900 mb-4">Summary</h2>
  <div class="prose prose-sm max-w-none text-gray-700">
    <%== simple_format(summary.content) %>
  </div>
<% else %>
  <h2 class="text-lg font-semibold text-gray-900 mb-4">Summary</h2>
  <div class="flex items-center gap-2 text-sm text-gray-500">
    <svg class="h-4 w-4 animate-spin" fill="none" viewBox="0 0 24 24">
      <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
      <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"></path>
    </svg>
    Generating summary...
  </div>
<% end %>
```

**Step 4: Create the action items partial**

```erb
<%# app/views/meetings/_action_items.html.erb %>
<h2 class="text-lg font-semibold text-gray-900 mb-4">Action Items</h2>

<% if action_items.any? %>
  <ul class="space-y-3">
    <% action_items.each do |item| %>
      <li class="flex items-start gap-3" data-controller="action-item" data-action-item-url-value="<%= meeting_action_item_path(item.meeting, item) %>">
        <input type="checkbox"
          <%= "checked" if item.completed? %>
          class="mt-0.5 h-4 w-4 rounded border-gray-300 text-indigo-600 focus:ring-indigo-600"
          data-action="change->action-item#toggle"
          data-action-item-target="checkbox">
        <div class="flex-1">
          <p class="text-sm text-gray-700 <%= 'line-through text-gray-400' if item.completed? %>">
            <%= item.description %>
          </p>
          <% if item.assignee.present? || item.due_date.present? %>
            <p class="text-xs text-gray-500 mt-1">
              <% if item.assignee.present? %>
                <span>Assigned to: <%= item.assignee %></span>
              <% end %>
              <% if item.due_date.present? %>
                <span class="ml-2">Due: <%= item.due_date.strftime("%b %d, %Y") %></span>
              <% end %>
            </p>
          <% end %>
        </div>
      </li>
    <% end %>
  </ul>
<% else %>
  <div class="flex items-center gap-2 text-sm text-gray-500">
    <svg class="h-4 w-4 animate-spin" fill="none" viewBox="0 0 24 24">
      <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
      <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"></path>
    </svg>
    Extracting action items...
  </div>
<% end %>
```

**Step 5: Commit**

```bash
git add -A && git commit -m "feat: add meeting show view with transcript, summary, and action items"
```

---

### Task 4: Upload Form (New Meeting)

**Files:**
- Create: `app/views/meetings/new.html.erb`
- Create: `app/views/meetings/_form.html.erb`
- Create: `app/javascript/controllers/file_upload_controller.js`

**Step 1: Create the new view**

```erb
<%# app/views/meetings/new.html.erb %>
<div class="max-w-2xl mx-auto">
  <h1 class="text-2xl font-bold text-gray-900 mb-8">Upload Meeting Recording</h1>

  <%= render "form", meeting: @meeting %>
</div>
```

**Step 2: Create the form partial**

```erb
<%# app/views/meetings/_form.html.erb %>
<%= form_with(model: meeting, class: "space-y-6", data: { controller: "file-upload" }) do |form| %>
  <% if meeting.errors.any? %>
    <div class="rounded-md bg-red-50 p-4">
      <h3 class="text-sm font-medium text-red-800">
        <%= pluralize(meeting.errors.count, "error") %> prevented this meeting from being saved:
      </h3>
      <ul class="mt-2 list-disc pl-5 text-sm text-red-700">
        <% meeting.errors.full_messages.each do |message| %>
          <li><%= message %></li>
        <% end %>
      </ul>
    </div>
  <% end %>

  <div>
    <%= form.label :title, class: "block text-sm font-medium text-gray-700" %>
    <%= form.text_field :title,
      class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm",
      placeholder: "e.g. Weekly Standup, Project Kickoff" %>
  </div>

  <div>
    <%= form.label :language, class: "block text-sm font-medium text-gray-700" %>
    <%= form.select :language,
      [
        ["English (US)", "en-US"],
        ["English (UK)", "en-GB"],
        ["Spanish (Spain)", "es-ES"],
        ["French (France)", "fr-FR"],
        ["German (Germany)", "de-DE"],
        ["Portuguese (Brazil)", "pt-BR"],
        ["Italian (Italy)", "it-IT"],
        ["Dutch (Netherlands)", "nl-NL"],
        ["Japanese (Japan)", "ja-JP"],
        ["Chinese Mandarin (Simplified)", "cmn-Hans-CN"]
      ],
      {},
      class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm" %>
  </div>

  <div>
    <%= form.label :recording, "Audio/Video File", class: "block text-sm font-medium text-gray-700" %>
    <div class="mt-1 flex justify-center rounded-md border-2 border-dashed border-gray-300 px-6 pt-5 pb-6"
         data-file-upload-target="dropzone">
      <div class="space-y-1 text-center">
        <svg class="mx-auto h-12 w-12 text-gray-400" stroke="currentColor" fill="none" viewBox="0 0 48 48">
          <path d="M28 8H12a4 4 0 00-4 4v20m32-12v8m0 0v8a4 4 0 01-4 4H12a4 4 0 01-4-4v-4m32-4l-3.172-3.172a4 4 0 00-5.656 0L28 28M8 32l9.172-9.172a4 4 0 015.656 0L28 28m0 0l4 4m4-24h8m-4-4v8m-12 4h.02"
            stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
        </svg>
        <div class="flex text-sm text-gray-600">
          <label class="relative cursor-pointer rounded-md font-medium text-indigo-600 hover:text-indigo-500">
            <span>Upload a file</span>
            <%= form.file_field :recording,
              accept: "audio/*,video/*",
              class: "sr-only",
              data: { file_upload_target: "input", action: "change->file-upload#fileSelected" } %>
          </label>
          <p class="pl-1">or drag and drop</p>
        </div>
        <p class="text-xs text-gray-500">MP3, WAV, MP4, WEBM, OGG up to 2GB</p>
        <p class="text-sm font-medium text-indigo-600 hidden" data-file-upload-target="filename"></p>
      </div>
    </div>
  </div>

  <div>
    <%= form.submit "Upload & Transcribe",
      class: "w-full rounded-md bg-indigo-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600",
      data: { file_upload_target: "submit" } %>
  </div>
<% end %>
```

**Step 3: Create the Stimulus file upload controller**

```javascript
// app/javascript/controllers/file_upload_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "filename", "submit", "dropzone"]

  fileSelected() {
    const file = this.inputTarget.files[0]
    if (file) {
      this.filenameTarget.textContent = `Selected: ${file.name} (${this.formatSize(file.size)})`
      this.filenameTarget.classList.remove("hidden")
    }
  }

  formatSize(bytes) {
    if (bytes < 1024) return `${bytes} B`
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
    if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
    return `${(bytes / (1024 * 1024 * 1024)).toFixed(1)} GB`
  }
}
```

**Step 4: Register the controller in importmap (if not auto-registered)**

The Stimulus controllers in `app/javascript/controllers/` are auto-loaded by `stimulus-rails`, so no manual registration is needed. Verify with:

Run: `grep -r "file_upload" app/javascript/controllers/`

**Step 5: Commit**

```bash
git add -A && git commit -m "feat: add meeting upload form with file upload Stimulus controller"
```

---

### Task 5: Action Item Toggle (Stimulus + Controller)

**Files:**
- Create: `app/javascript/controllers/action_item_controller.js`
- Add route: nested `action_items` under `meetings`
- Create: `app/controllers/action_items_controller.rb`
- Test: `test/controllers/action_items_controller_test.rb`

**Step 1: Add nested route**

```ruby
# config/routes.rb — update meetings resources
resources :meetings, only: [:index, :show, :new, :create, :destroy] do
  resources :action_items, only: [:update]
  resources :follow_up_emails, only: [:new, :create]
end
```

**Step 2: Create the Stimulus controller**

```javascript
// app/javascript/controllers/action_item_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox"]
  static values = { url: String }

  toggle() {
    const completed = this.checkboxTarget.checked

    fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("[name='csrf-token']").content,
        "Accept": "text/vnd.turbo-stream.html"
      },
      body: JSON.stringify({ action_item: { completed: completed } })
    })
  }
}
```

**Step 3: Create the ActionItems controller**

```ruby
# app/controllers/action_items_controller.rb
class ActionItemsController < ApplicationController
  before_action :set_meeting
  before_action :set_action_item

  def update
    @action_item.update!(action_item_params)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "meeting_#{@meeting.id}_action_items",
          partial: "meetings/action_items",
          locals: { action_items: @meeting.action_items }
        )
      end
      format.html { redirect_to @meeting }
    end
  end

  private

  def set_meeting
    @meeting = Current.user.meetings.find(params[:meeting_id])
  end

  def set_action_item
    @action_item = @meeting.action_items.find(params[:id])
  end

  def action_item_params
    params.require(:action_item).permit(:completed)
  end
end
```

**Step 4: Write controller tests**

```ruby
# test/controllers/action_items_controller_test.rb
require "test_helper"

class ActionItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
    @meeting = meetings(:one)
    @action_item = action_items(:one)
  end

  test "update toggles completed status" do
    assert_not @action_item.completed?

    patch meeting_action_item_url(@meeting, @action_item), params: {
      action_item: { completed: true }
    }, as: :turbo_stream

    assert_response :success
    assert @action_item.reload.completed?
  end

  test "update requires authentication" do
    sign_out
    patch meeting_action_item_url(@meeting, @action_item), params: {
      action_item: { completed: true }
    }
    assert_redirected_to new_session_url
  end
end
```

**Step 5: Run tests**

Run: `bin/rails test test/controllers/action_items_controller_test.rb`
Expected: All tests PASS

**Step 6: Commit**

```bash
git add -A && git commit -m "feat: add action item toggle with Stimulus controller and turbo stream response"
```

---

### Task 6: System Tests for Core Flows

**Files:**
- Create: `test/system/meetings_test.rb`

**Step 1: Write system tests for the main user flows**

```ruby
# test/system/meetings_test.rb
require "application_system_test_case"

class MeetingsTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    # Sign in
    visit new_session_url
    fill_in "Email address", with: @user.email_address
    fill_in "Password", with: "password"
    click_on "Sign in"
  end

  test "visiting the index" do
    visit meetings_url
    assert_selector "h1", text: /meetings/i
  end

  test "viewing a completed meeting" do
    visit meeting_url(meetings(:one))
    assert_selector "h1", text: "Weekly Standup"
    assert_text "Summary"
    assert_text "Action Items"
  end

  test "navigating to new meeting form" do
    visit meetings_url
    click_on "Upload Meeting"
    assert_selector "h1", text: "Upload Meeting Recording"
  end
end
```

**Step 2: Run system tests**

Run: `bin/rails test:system`
Expected: All tests PASS

**Step 3: Commit**

```bash
git add -A && git commit -m "test: add system tests for core meeting flows"
```
