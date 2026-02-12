# Spec 7: Follow-up Emails

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Let users compose and send follow-up emails with pre-filled meeting summary and action items, displayed inline via Turbo Frame on the meeting show page.

**Architecture:** A `FollowUpEmailsController` renders a form inside a Turbo Frame on the meeting show page. A `FollowUpComposer` service generates the default email body. The `FollowUpMailer` sends via Action Mailer / SMTP. Sent emails are stored as `FollowUpEmail` records.

**Tech Stack:** Action Mailer, Turbo Frames, Tailwind CSS.

**Dependencies:** Spec 1 (FollowUpEmail model), Spec 6 (Turbo Frame target on show page).

---

### Task 1: FollowUpComposer Service

**Files:**
- Create: `app/services/follow_up_composer.rb`
- Test: `test/services/follow_up_composer_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/services/follow_up_composer_test.rb
require "test_helper"

class FollowUpComposerTest < ActiveSupport::TestCase
  test "generates default subject from meeting title" do
    meeting = meetings(:one)
    composer = FollowUpComposer.new(meeting)

    assert_equal "Follow-up: Weekly Standup", composer.subject
  end

  test "generates body with summary content" do
    meeting = meetings(:one)
    composer = FollowUpComposer.new(meeting)
    body = composer.body

    assert_includes body, "Weekly Standup"
    assert_includes body, meeting.summary.content
  end

  test "generates body with action items" do
    meeting = meetings(:one)
    composer = FollowUpComposer.new(meeting)
    body = composer.body

    assert_includes body, "Action Items"
    assert_includes body, action_items(:one).description
    assert_includes body, action_items(:two).description
  end

  test "includes assignee in action items when present" do
    meeting = meetings(:one)
    composer = FollowUpComposer.new(meeting)
    body = composer.body

    assert_includes body, "Sarah"
  end

  test "handles meeting without summary gracefully" do
    meeting = meetings(:two) # No summary
    composer = FollowUpComposer.new(meeting)
    body = composer.body

    assert_includes body, "Project Kickoff"
    assert_not_includes body, "Summary"
  end

  test "handles meeting without action items gracefully" do
    meeting = meetings(:two) # No action items
    composer = FollowUpComposer.new(meeting)
    body = composer.body

    assert_not_includes body, "Action Items"
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/follow_up_composer_test.rb`
Expected: FAIL

**Step 3: Implement the composer**

```ruby
# app/services/follow_up_composer.rb
class FollowUpComposer
  def initialize(meeting)
    @meeting = meeting
  end

  def subject
    "Follow-up: #{@meeting.title}"
  end

  def body
    parts = []
    parts << "Hi everyone,"
    parts << ""
    parts << "Here's a summary of our meeting: #{@meeting.title}"

    if @meeting.summary.present?
      parts << ""
      parts << "## Summary"
      parts << ""
      parts << @meeting.summary.content
    end

    if @meeting.action_items.any?
      parts << ""
      parts << "## Action Items"
      parts << ""
      @meeting.action_items.each do |item|
        line = "- #{item.description}"
        line += " (assigned to: #{item.assignee})" if item.assignee.present?
        line += " [due: #{item.due_date.strftime('%b %d, %Y')}]" if item.due_date.present?
        parts << line
      end
    end

    parts << ""
    parts << "Best regards"

    parts.join("\n")
  end
end
```

**Step 4: Run tests**

Run: `bin/rails test test/services/follow_up_composer_test.rb`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add -A && git commit -m "feat: add FollowUpComposer service for email body generation"
```

---

### Task 2: FollowUpMailer

**Files:**
- Create: `app/mailers/follow_up_mailer.rb`
- Create: `app/views/follow_up_mailer/follow_up.html.erb`
- Create: `app/views/follow_up_mailer/follow_up.text.erb`
- Test: `test/mailers/follow_up_mailer_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/mailers/follow_up_mailer_test.rb
require "test_helper"

class FollowUpMailerTest < ActionMailer::TestCase
  test "follow_up sends to all recipients" do
    follow_up_email = follow_up_emails(:one)

    mail = FollowUpMailer.follow_up(follow_up_email)

    assert_equal ["alice@example.com", "bob@example.com"], mail.to
    assert_equal "Follow-up: Weekly Standup", mail.subject
    assert_includes mail.body.encoded, "Here is the meeting summary"
  end

  test "follow_up includes meeting title in body" do
    follow_up_email = follow_up_emails(:one)
    mail = FollowUpMailer.follow_up(follow_up_email)

    assert_includes mail.body.encoded, follow_up_email.body
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/mailers/follow_up_mailer_test.rb`
Expected: FAIL

**Step 3: Implement the mailer**

```ruby
# app/mailers/follow_up_mailer.rb
class FollowUpMailer < ApplicationMailer
  def follow_up(follow_up_email)
    @follow_up_email = follow_up_email
    @meeting = follow_up_email.meeting

    mail(
      to: follow_up_email.recipient_list,
      subject: follow_up_email.subject
    )
  end
end
```

**Step 4: Create the email templates**

```erb
<%# app/views/follow_up_mailer/follow_up.html.erb %>
<div style="font-family: sans-serif; max-width: 600px; margin: 0 auto;">
  <%== simple_format(@follow_up_email.body) %>
</div>
```

```text
<%# app/views/follow_up_mailer/follow_up.text.erb %>
<%= @follow_up_email.body %>
```

**Step 5: Run tests**

Run: `bin/rails test test/mailers/follow_up_mailer_test.rb`
Expected: All tests PASS

**Step 6: Create mailer preview**

```ruby
# test/mailers/previews/follow_up_mailer_preview.rb
class FollowUpMailerPreview < ActionMailer::Preview
  def follow_up
    follow_up_email = FollowUpEmail.first || FollowUpEmail.new(
      recipients: "test@example.com",
      subject: "Follow-up: Sample Meeting",
      body: "Hi everyone,\n\nHere's a summary of our meeting.\n\n## Summary\nThe team discussed project progress.\n\n## Action Items\n- Complete the API integration (assigned to: Sarah)\n- Schedule follow-up meeting\n\nBest regards"
    )
    FollowUpMailer.follow_up(follow_up_email)
  end
end
```

**Step 7: Commit**

```bash
git add -A && git commit -m "feat: add FollowUpMailer with HTML and text templates"
```

---

### Task 3: FollowUpEmailsController

**Files:**
- Create: `app/controllers/follow_up_emails_controller.rb`
- Test: `test/controllers/follow_up_emails_controller_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/controllers/follow_up_emails_controller_test.rb
require "test_helper"

class FollowUpEmailsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
    @meeting = meetings(:one) # completed meeting with summary and action items
  end

  test "new renders form in turbo frame" do
    get new_meeting_follow_up_email_url(@meeting)
    assert_response :success
    assert_select "turbo-frame#follow_up_email"
    assert_select "form"
  end

  test "new pre-fills subject and body" do
    get new_meeting_follow_up_email_url(@meeting)
    assert_response :success
    assert_select "input[name='follow_up_email[subject]'][value=?]", "Follow-up: Weekly Standup"
  end

  test "create sends email and saves record" do
    assert_difference("FollowUpEmail.count") do
      assert_emails 1 do
        post meeting_follow_up_emails_url(@meeting), params: {
          follow_up_email: {
            recipients: "alice@example.com, bob@example.com",
            subject: "Follow-up: Weekly Standup",
            body: "Here is the follow-up..."
          }
        }
      end
    end

    follow_up = FollowUpEmail.last
    assert_equal @meeting, follow_up.meeting
    assert_not_nil follow_up.sent_at
    assert_redirected_to meeting_url(@meeting)
  end

  test "create with missing recipients renders errors" do
    assert_no_difference("FollowUpEmail.count") do
      post meeting_follow_up_emails_url(@meeting), params: {
        follow_up_email: {
          recipients: "",
          subject: "Test",
          body: "Body"
        }
      }
    end

    assert_response :unprocessable_entity
  end

  test "requires authentication" do
    sign_out
    get new_meeting_follow_up_email_url(@meeting)
    assert_redirected_to new_session_url
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/follow_up_emails_controller_test.rb`
Expected: FAIL

**Step 3: Implement the controller**

```ruby
# app/controllers/follow_up_emails_controller.rb
class FollowUpEmailsController < ApplicationController
  before_action :set_meeting

  def new
    composer = FollowUpComposer.new(@meeting)
    @follow_up_email = @meeting.follow_up_emails.build(
      subject: composer.subject,
      body: composer.body
    )
  end

  def create
    @follow_up_email = @meeting.follow_up_emails.build(follow_up_email_params)

    if @follow_up_email.save
      FollowUpMailer.follow_up(@follow_up_email).deliver_later
      @follow_up_email.update!(sent_at: Time.current)
      redirect_to @meeting, notice: "Follow-up email sent successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_meeting
    @meeting = Current.user.meetings.find(params[:meeting_id])
  end

  def follow_up_email_params
    params.require(:follow_up_email).permit(:recipients, :subject, :body)
  end
end
```

**Step 4: Run tests**

Run: `bin/rails test test/controllers/follow_up_emails_controller_test.rb`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add -A && git commit -m "feat: add FollowUpEmailsController with Turbo Frame rendering"
```

---

### Task 4: Follow-up Email Views (Turbo Frame)

**Files:**
- Create: `app/views/follow_up_emails/new.html.erb`

**Step 1: Create the new view (renders inside Turbo Frame)**

```erb
<%# app/views/follow_up_emails/new.html.erb %>
<%= turbo_frame_tag "follow_up_email" do %>
  <div class="space-y-4">
    <h3 class="text-lg font-semibold text-gray-900">Send Follow-up Email</h3>

    <%= form_with(model: [@meeting, @follow_up_email], class: "space-y-4") do |form| %>
      <% if @follow_up_email.errors.any? %>
        <div class="rounded-md bg-red-50 p-4">
          <ul class="list-disc pl-5 text-sm text-red-700">
            <% @follow_up_email.errors.full_messages.each do |message| %>
              <li><%= message %></li>
            <% end %>
          </ul>
        </div>
      <% end %>

      <div>
        <%= form.label :recipients, "To (comma-separated emails)", class: "block text-sm font-medium text-gray-700" %>
        <%= form.text_field :recipients,
          class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm",
          placeholder: "alice@example.com, bob@example.com" %>
      </div>

      <div>
        <%= form.label :subject, class: "block text-sm font-medium text-gray-700" %>
        <%= form.text_field :subject,
          class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm" %>
      </div>

      <div>
        <%= form.label :body, class: "block text-sm font-medium text-gray-700" %>
        <%= form.text_area :body,
          rows: 15,
          class: "mt-1 block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-500 focus:ring-indigo-500 sm:text-sm font-mono" %>
      </div>

      <div class="flex gap-3">
        <%= form.submit "Send Email",
          class: "rounded-md bg-indigo-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500" %>
        <%= link_to "Cancel", meeting_path(@meeting),
          class: "rounded-md bg-white px-4 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50",
          data: { turbo_frame: "follow_up_email" } %>
      </div>
    <% end %>

    <%# Show previously sent emails %>
    <% if @meeting.follow_up_emails.any? %>
      <div class="mt-6 border-t border-gray-200 pt-4">
        <h4 class="text-sm font-medium text-gray-700 mb-2">Previously Sent</h4>
        <ul class="space-y-2">
          <% @meeting.follow_up_emails.order(sent_at: :desc).each do |email| %>
            <li class="text-sm text-gray-500">
              Sent to <%= email.recipients %> on <%= email.sent_at&.strftime("%b %d, %Y at %I:%M %p") %>
            </li>
          <% end %>
        </ul>
      </div>
    <% end %>
  </div>
<% end %>
```

**Step 2: Commit**

```bash
git add -A && git commit -m "feat: add follow-up email form view with Turbo Frame"
```
