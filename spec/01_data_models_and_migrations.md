# Spec 1: Data Models & Migrations

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create all domain models, migrations, and associations needed for the meeting transcription pipeline.

**Architecture:** Six new models built on top of the existing User/Session auth models. Simple Rails enums for status tracking (no state machine gem). All models belong to a User through Meeting.

**Tech Stack:** Rails 8.1, PostgreSQL with pgvector, Active Storage, Action Text, `neighbor` gem for vector columns.

---

## Existing State

Already built:

- `User` model with `has_secure_password`, `has_many :sessions`
- `Session` model (auth sessions)
- Active Storage tables (blobs, attachments, variant_records)
- pgvector extension enabled

Not yet built: Action Text tables, all domain models below.

---

## Data Model Overview

```
User
  has_many :meetings

Meeting
  belongs_to :user
  has_one :transcript
  has_one :summary
  has_many :action_items
  has_many :follow_up_emails
  has_one_attached :recording

Transcript
  belongs_to :meeting
  has_many :transcript_segments
  has_many :transcript_chunks
  has_rich_text :content          # via Action Text

TranscriptSegment
  belongs_to :transcript

Summary
  belongs_to :meeting
  has_rich_text :content          # via Action Text

ActionItem
  belongs_to :meeting

TranscriptChunk
  belongs_to :transcript
  (has vector embedding via neighbor gem)

FollowUpEmail
  belongs_to :meeting
  has_rich_text :body             # via Action Text
```

---

### Task 0: Install Action Text

**Goal:** Set up Action Text so that Transcript, Summary, and FollowUpEmail can use `has_rich_text` for rich content storage.

**Step 1: Install Action Text**

Run: `bin/rails action_text:install`

This creates:
- Migration for `action_text_rich_texts` table
- `app/models/concerns/action_text/...` (if not already present)
- Adds `trix` and `@rails/actiontext` to JS bundle

**Step 2: Run the migration**

Run: `bin/rails db:migrate`

**Step 3: Verify**

Run: `bin/rails runner "puts ActionText::RichText.table_name"`
Expected: `action_text_rich_texts`

**Step 4: Commit**

```bash
git add -A && git commit -m "feat: install Action Text for rich content storage"
```

---

### Task 1: Meeting Model & Migration

**Files:**

- Create: `db/migrate/TIMESTAMP_create_meetings.rb`
- Create: `app/models/meeting.rb`
- Modify: `app/models/user.rb`
- Test: `test/models/meeting_test.rb`
- Test: `test/fixtures/meetings.yml`

**Step 1: Write the failing tests**

```ruby
# test/models/meeting_test.rb
require "test_helper"

class MeetingTest < ActiveSupport::TestCase
  test "valid meeting with required attributes" do
    meeting = Meeting.new(
      title: "Weekly Standup",
      language: "en-US",
      user: users(:one)
    )
    assert meeting.valid?
  end

  test "requires a title" do
    meeting = Meeting.new(language: "en-US", user: users(:one))
    assert_not meeting.valid?
    assert_includes meeting.errors[:title], "can't be blank"
  end

  test "requires a user" do
    meeting = Meeting.new(title: "Test", language: "en-US")
    assert_not meeting.valid?
    assert_includes meeting.errors[:user], "must exist"
  end

  test "defaults status to uploading" do
    meeting = Meeting.new
    assert_equal "uploading", meeting.status
  end

  test "defaults language to en-US" do
    meeting = Meeting.new
    assert_equal "en-US", meeting.language
  end

  test "status enum values" do
    assert_equal(
      { "uploading" => "uploading", "transcribing" => "transcribing",
        "transcribed" => "transcribed", "processing" => "processing",
        "completed" => "completed", "failed" => "failed" },
      Meeting.statuses
    )
  end

  test "belongs to user" do
    meeting = meetings(:one)
    assert_instance_of User, meeting.user
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/models/meeting_test.rb`
Expected: FAIL — `NameError: uninitialized constant Meeting`

**Step 3: Create the migration**

```ruby
# db/migrate/TIMESTAMP_create_meetings.rb
class CreateMeetings < ActiveRecord::Migration[8.1]
  def change
    create_table :meetings do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.string :language, null: false, default: "en-US"
      t.string :status, null: false, default: "uploading"
      t.string :google_calendar_event_id

      t.timestamps
    end

    add_index :meetings, :status
    add_index :meetings, [:user_id, :created_at]
  end
end
```

**Step 4: Create the model**

```ruby
# app/models/meeting.rb
class Meeting < ApplicationRecord
  belongs_to :user
  has_one :transcript, dependent: :destroy
  has_one :summary, dependent: :destroy
  has_many :action_items, dependent: :destroy
  has_many :follow_up_emails, dependent: :destroy
  has_one_attached :recording

  enum :status, {
    uploading: "uploading",
    transcribing: "transcribing",
    transcribed: "transcribed",
    processing: "processing",
    completed: "completed",
    failed: "failed"
  }, default: :uploading

  validates :title, presence: true
  validates :language, presence: true

  # Called by AI jobs after completion. Transitions to completed
  # only when both summary and action items exist.
  def check_processing_complete!
    return unless summary.present? && action_items.any?
    update!(status: :completed)
  end
end
```

**Step 5: Update User model**

```ruby
# app/models/user.rb — add association
has_many :meetings, dependent: :destroy
```

**Step 6: Create fixtures**

```yaml
# test/fixtures/meetings.yml
one:
  title: "Weekly Standup"
  language: "en-US"
  status: "completed"
  user: one

two:
  title: "Project Kickoff"
  language: "en-US"
  status: "uploading"
  user: one

failed:
  title: "Failed Meeting"
  language: "en-US"
  status: "failed"
  user: one
```

**Step 7: Run migration and tests**

Run: `bin/rails db:migrate && bin/rails test test/models/meeting_test.rb`
Expected: All tests PASS

**Step 8: Commit**

```bash
git add -A && git commit -m "feat: add Meeting model with status enum and user association"
```

---

### Task 2: Transcript Model & Migration

**Files:**

- Create: `db/migrate/TIMESTAMP_create_transcripts.rb`
- Create: `app/models/transcript.rb`
- Test: `test/models/transcript_test.rb`
- Test: `test/fixtures/transcripts.yml`

**Note:** The transcript's rich text content (formatted speaker dialogue) is stored via Action Text (`has_rich_text :content`) rather than a `raw_content` text column. The `raw_response` jsonb column is kept for storing the raw API response from HappyScribe.

**Step 1: Write the failing tests**

```ruby
# test/models/transcript_test.rb
require "test_helper"

class TranscriptTest < ActiveSupport::TestCase
  test "valid transcript" do
    transcript = Transcript.new(
      meeting: meetings(:one),
      status: :pending
    )
    assert transcript.valid?
  end

  test "requires a meeting" do
    transcript = Transcript.new(status: :pending)
    assert_not transcript.valid?
  end

  test "defaults status to pending" do
    transcript = Transcript.new
    assert_equal "pending", transcript.status
  end

  test "status enum values" do
    assert_equal(
      { "pending" => "pending", "processing" => "processing",
        "completed" => "completed", "failed" => "failed" },
      Transcript.statuses
    )
  end

  test "belongs to meeting" do
    transcript = transcripts(:one)
    assert_instance_of Meeting, transcript.meeting
  end

  test "stores happyscribe_id" do
    transcript = transcripts(:one)
    transcript.update!(happyscribe_id: "abc123")
    assert_equal "abc123", transcript.reload.happyscribe_id
  end

  test "stores rich text content via Action Text" do
    transcript = transcripts(:one)
    transcript.update!(content: "<p>Speaker 1: Hello everyone.</p>")
    assert_equal "<p>Speaker 1: Hello everyone.</p>", transcript.content.to_plain_text.strip.presence && transcript.content.body.to_html
    assert transcript.content.present?
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/models/transcript_test.rb`
Expected: FAIL

**Step 3: Create the migration**

```ruby
# db/migrate/TIMESTAMP_create_transcripts.rb
class CreateTranscripts < ActiveRecord::Migration[8.1]
  def change
    create_table :transcripts do |t|
      t.references :meeting, null: false, foreign_key: true
      t.string :happyscribe_id
      t.string :happyscribe_export_id
      t.jsonb :raw_response
      t.string :status, null: false, default: "pending"
      t.integer :audio_length_seconds

      t.timestamps
    end

    add_index :transcripts, :happyscribe_id, unique: true
    add_index :transcripts, :status
  end
end
```

**Step 4: Create the model**

```ruby
# app/models/transcript.rb
class Transcript < ApplicationRecord
  belongs_to :meeting
  has_many :transcript_segments, dependent: :destroy
  has_many :transcript_chunks, dependent: :destroy

  has_rich_text :content

  enum :status, {
    pending: "pending",
    processing: "processing",
    completed: "completed",
    failed: "failed"
  }, default: :pending

  # Returns the full transcript as formatted text with speaker labels
  def formatted_text
    transcript_segments.order(:position).map do |segment|
      timestamp = format_timestamp(segment.start_time)
      "#{segment.speaker} [#{timestamp}]: #{segment.content}"
    end.join("\n\n")
  end

  private

  def format_timestamp(seconds)
    return "00:00:00" if seconds.nil?
    Time.at(seconds).utc.strftime("%H:%M:%S")
  end
end
```

**Step 5: Create fixtures**

```yaml
# test/fixtures/transcripts.yml
one:
  meeting: one
  happyscribe_id: "hs_transcript_001"
  status: "completed"
  audio_length_seconds: 120

two:
  meeting: two
  status: "pending"
```

**Step 6: Run migration and tests**

Run: `bin/rails db:migrate && bin/rails test test/models/transcript_test.rb`
Expected: All tests PASS

**Step 7: Commit**

```bash
git add -A && git commit -m "feat: add Transcript model with Action Text content and HappyScribe ID"
```

---

### Task 3: TranscriptSegment Model & Migration

**Files:**

- Create: `db/migrate/TIMESTAMP_create_transcript_segments.rb`
- Create: `app/models/transcript_segment.rb`
- Test: `test/models/transcript_segment_test.rb`
- Test: `test/fixtures/transcript_segments.yml`

**Step 1: Write the failing tests**

```ruby
# test/models/transcript_segment_test.rb
require "test_helper"

class TranscriptSegmentTest < ActiveSupport::TestCase
  test "valid segment with required attributes" do
    segment = TranscriptSegment.new(
      transcript: transcripts(:one),
      speaker: "Speaker 1",
      content: "Hello everyone, welcome to the meeting.",
      start_time: 0.0,
      end_time: 5.5,
      position: 0
    )
    assert segment.valid?
  end

  test "requires a transcript" do
    segment = TranscriptSegment.new(
      speaker: "Speaker 1",
      content: "Hello",
      position: 0
    )
    assert_not segment.valid?
  end

  test "requires content" do
    segment = TranscriptSegment.new(
      transcript: transcripts(:one),
      speaker: "Speaker 1",
      position: 0
    )
    assert_not segment.valid?
    assert_includes segment.errors[:content], "can't be blank"
  end

  test "requires position" do
    segment = TranscriptSegment.new(
      transcript: transcripts(:one),
      speaker: "Speaker 1",
      content: "Hello"
    )
    assert_not segment.valid?
    assert_includes segment.errors[:position], "can't be blank"
  end

  test "orders by position by default" do
    # Segments should come back ordered by position
    segments = transcripts(:one).transcript_segments.order(:position)
    positions = segments.map(&:position)
    assert_equal positions.sort, positions
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/models/transcript_segment_test.rb`
Expected: FAIL

**Step 3: Create the migration**

```ruby
# db/migrate/TIMESTAMP_create_transcript_segments.rb
class CreateTranscriptSegments < ActiveRecord::Migration[8.1]
  def change
    create_table :transcript_segments do |t|
      t.references :transcript, null: false, foreign_key: true
      t.string :speaker
      t.text :content, null: false
      t.float :start_time
      t.float :end_time
      t.integer :position, null: false

      t.timestamps
    end

    add_index :transcript_segments, [:transcript_id, :position]
  end
end
```

**Step 4: Create the model**

```ruby
# app/models/transcript_segment.rb
class TranscriptSegment < ApplicationRecord
  belongs_to :transcript

  validates :content, presence: true
  validates :position, presence: true

  default_scope { order(:position) }
end
```

**Step 5: Create fixtures**

```yaml
# test/fixtures/transcript_segments.yml
one_first:
  transcript: one
  speaker: "Speaker 1"
  content: "Hello everyone, welcome to the weekly standup."
  start_time: 0.0
  end_time: 3.5
  position: 0

one_second:
  transcript: one
  speaker: "Speaker 2"
  content: "Thanks. My update is that the API integration is done."
  start_time: 3.5
  end_time: 8.2
  position: 1

one_third:
  transcript: one
  speaker: "Speaker 1"
  content: "Great work. Let's move on to the next topic."
  start_time: 8.2
  end_time: 11.0
  position: 2
```

**Step 6: Run migration and tests**

Run: `bin/rails db:migrate && bin/rails test test/models/transcript_segment_test.rb`
Expected: All tests PASS

**Step 7: Commit**

```bash
git add -A && git commit -m "feat: add TranscriptSegment model with speaker labels and positioning"
```

---

### Task 4: Summary Model & Migration

**Files:**

- Create: `db/migrate/TIMESTAMP_create_summaries.rb`
- Create: `app/models/summary.rb`
- Test: `test/models/summary_test.rb`
- Test: `test/fixtures/summaries.yml`

**Note:** Summary content is stored via Action Text (`has_rich_text :content`) for rich text rendering of AI-generated summaries.

**Step 1: Write the failing tests**

```ruby
# test/models/summary_test.rb
require "test_helper"

class SummaryTest < ActiveSupport::TestCase
  test "valid summary" do
    summary = Summary.new(
      meeting: meetings(:two),
      content: "This meeting covered project updates.",
      model_used: "claude-sonnet-4-20250514"
    )
    assert summary.valid?
  end

  test "requires a meeting" do
    summary = Summary.new(content: "Summary text", model_used: "claude-sonnet-4-20250514")
    assert_not summary.valid?
  end

  test "requires content" do
    summary = Summary.new(meeting: meetings(:two), model_used: "claude-sonnet-4-20250514")
    assert_not summary.valid?
    assert_includes summary.errors[:content], "can't be blank"
  end

  test "belongs to meeting" do
    summary = summaries(:one)
    assert_instance_of Meeting, summary.meeting
  end

  test "stores rich text content via Action Text" do
    summary = summaries(:one)
    summary.update!(content: "<h2>Summary</h2><p>The team discussed progress.</p>")
    assert summary.content.present?
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/models/summary_test.rb`
Expected: FAIL

**Step 3: Create the migration**

```ruby
# db/migrate/TIMESTAMP_create_summaries.rb
class CreateSummaries < ActiveRecord::Migration[8.1]
  def change
    create_table :summaries do |t|
      t.references :meeting, null: false, foreign_key: true
      t.string :model_used

      t.timestamps
    end

    add_index :summaries, :meeting_id, unique: true
  end
end
```

**Step 4: Create the model**

```ruby
# app/models/summary.rb
class Summary < ApplicationRecord
  belongs_to :meeting

  has_rich_text :content

  validates :content, presence: true
end
```

**Step 5: Create fixtures**

```yaml
# test/fixtures/summaries.yml
one:
  meeting: one
  model_used: "claude-sonnet-4-20250514"
```

Note: Rich text content for fixtures must be set up in test setup or via `ActionText::RichText` fixture entries. For simplicity, assign content in test code:

```ruby
# In test setup or individual tests:
summaries(:one).update!(content: "The team discussed project progress. API integration is complete.")
```

**Step 6: Run migration and tests**

Run: `bin/rails db:migrate && bin/rails test test/models/summary_test.rb`
Expected: All tests PASS

**Step 7: Commit**

```bash
git add -A && git commit -m "feat: add Summary model with Action Text content for AI-generated summaries"
```

---

### Task 5: ActionItem Model & Migration

**Files:**

- Create: `db/migrate/TIMESTAMP_create_action_items.rb`
- Create: `app/models/action_item.rb`
- Test: `test/models/action_item_test.rb`
- Test: `test/fixtures/action_items.yml`

**Step 1: Write the failing tests**

```ruby
# test/models/action_item_test.rb
require "test_helper"

class ActionItemTest < ActiveSupport::TestCase
  test "valid action item" do
    item = ActionItem.new(
      meeting: meetings(:one),
      description: "Send the Q3 report to finance team"
    )
    assert item.valid?
  end

  test "requires description" do
    item = ActionItem.new(meeting: meetings(:one))
    assert_not item.valid?
    assert_includes item.errors[:description], "can't be blank"
  end

  test "requires a meeting" do
    item = ActionItem.new(description: "Do something")
    assert_not item.valid?
  end

  test "defaults completed to false" do
    item = ActionItem.new
    assert_equal false, item.completed
  end

  test "assignee is optional" do
    item = ActionItem.new(
      meeting: meetings(:one),
      description: "Do something",
      assignee: nil
    )
    assert item.valid?
  end

  test "due_date is optional" do
    item = ActionItem.new(
      meeting: meetings(:one),
      description: "Do something",
      due_date: nil
    )
    assert item.valid?
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/models/action_item_test.rb`
Expected: FAIL

**Step 3: Create the migration**

```ruby
# db/migrate/TIMESTAMP_create_action_items.rb
class CreateActionItems < ActiveRecord::Migration[8.1]
  def change
    create_table :action_items do |t|
      t.references :meeting, null: false, foreign_key: true
      t.text :description, null: false
      t.string :assignee
      t.date :due_date
      t.boolean :completed, null: false, default: false

      t.timestamps
    end

    add_index :action_items, [:meeting_id, :completed]
  end
end
```

**Step 4: Create the model**

```ruby
# app/models/action_item.rb
class ActionItem < ApplicationRecord
  belongs_to :meeting

  validates :description, presence: true

  scope :pending, -> { where(completed: false) }
  scope :done, -> { where(completed: true) }
end
```

**Step 5: Create fixtures**

```yaml
# test/fixtures/action_items.yml
one:
  meeting: one
  description: "Send the Q3 report to the finance team"
  assignee: "Sarah"
  completed: false

two:
  meeting: one
  description: "Schedule follow-up meeting for next week"
  assignee: "Tom"
  due_date: "2026-02-19"
  completed: false
```

**Step 6: Run migration and tests**

Run: `bin/rails db:migrate && bin/rails test test/models/action_item_test.rb`
Expected: All tests PASS

**Step 7: Commit**

```bash
git add -A && git commit -m "feat: add ActionItem model with completion tracking"
```

---

### Task 6: TranscriptChunk Model & Migration (with vector embedding)

**Files:**

- Create: `db/migrate/TIMESTAMP_create_transcript_chunks.rb`
- Create: `app/models/transcript_chunk.rb`
- Test: `test/models/transcript_chunk_test.rb`
- Test: `test/fixtures/transcript_chunks.yml`

**Step 1: Write the failing tests**

```ruby
# test/models/transcript_chunk_test.rb
require "test_helper"

class TranscriptChunkTest < ActiveSupport::TestCase
  test "valid chunk" do
    chunk = TranscriptChunk.new(
      transcript: transcripts(:one),
      content: "Speaker 1: Hello everyone.",
      position: 0
    )
    assert chunk.valid?
  end

  test "requires content" do
    chunk = TranscriptChunk.new(
      transcript: transcripts(:one),
      position: 0
    )
    assert_not chunk.valid?
    assert_includes chunk.errors[:content], "can't be blank"
  end

  test "requires position" do
    chunk = TranscriptChunk.new(
      transcript: transcripts(:one),
      content: "Some text"
    )
    assert_not chunk.valid?
    assert_includes chunk.errors[:position], "can't be blank"
  end

  test "requires a transcript" do
    chunk = TranscriptChunk.new(content: "Some text", position: 0)
    assert_not chunk.valid?
  end

  test "belongs to transcript" do
    chunk = transcript_chunks(:one)
    assert_instance_of Transcript, chunk.transcript
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/models/transcript_chunk_test.rb`
Expected: FAIL

**Step 3: Create the migration**

```ruby
# db/migrate/TIMESTAMP_create_transcript_chunks.rb
class CreateTranscriptChunks < ActiveRecord::Migration[8.1]
  def change
    create_table :transcript_chunks do |t|
      t.references :transcript, null: false, foreign_key: true
      t.text :content, null: false
      t.vector :embedding, limit: 1536
      t.integer :position, null: false
      t.float :start_time
      t.float :end_time

      t.timestamps
    end

    add_index :transcript_chunks, [:transcript_id, :position]
  end
end
```

**Step 4: Create the model**

```ruby
# app/models/transcript_chunk.rb
class TranscriptChunk < ApplicationRecord
  belongs_to :transcript

  has_neighbors :embedding

  validates :content, presence: true
  validates :position, presence: true
end
```

**Step 5: Create fixtures**

```yaml
# test/fixtures/transcript_chunks.yml
one:
  transcript: one
  content: "Speaker 1 [00:00:00]: Hello everyone, welcome to the weekly standup.\n\nSpeaker 2 [00:00:03]: Thanks. My update is that the API integration is done."
  position: 0
  start_time: 0.0
  end_time: 8.2
```

**Step 6: Run migration and tests**

Run: `bin/rails db:migrate && bin/rails test test/models/transcript_chunk_test.rb`
Expected: All tests PASS

**Step 7: Commit**

```bash
git add -A && git commit -m "feat: add TranscriptChunk model with pgvector embedding column"
```

---

### Task 7: FollowUpEmail Model & Migration

**Files:**

- Create: `db/migrate/TIMESTAMP_create_follow_up_emails.rb`
- Create: `app/models/follow_up_email.rb`
- Test: `test/models/follow_up_email_test.rb`
- Test: `test/fixtures/follow_up_emails.yml`

**Note:** The email body is stored via Action Text (`has_rich_text :body`) for rich formatting of follow-up emails.

**Step 1: Write the failing tests**

```ruby
# test/models/follow_up_email_test.rb
require "test_helper"

class FollowUpEmailTest < ActiveSupport::TestCase
  test "valid follow-up email" do
    email = FollowUpEmail.new(
      meeting: meetings(:one),
      recipients: "alice@example.com, bob@example.com",
      subject: "Follow-up: Weekly Standup",
      body: "Here is the summary...",
      sent_at: Time.current
    )
    assert email.valid?
  end

  test "requires recipients" do
    email = FollowUpEmail.new(
      meeting: meetings(:one),
      subject: "Test",
      body: "Body"
    )
    assert_not email.valid?
    assert_includes email.errors[:recipients], "can't be blank"
  end

  test "requires subject" do
    email = FollowUpEmail.new(
      meeting: meetings(:one),
      recipients: "test@example.com",
      body: "Body"
    )
    assert_not email.valid?
    assert_includes email.errors[:subject], "can't be blank"
  end

  test "requires body" do
    email = FollowUpEmail.new(
      meeting: meetings(:one),
      recipients: "test@example.com",
      subject: "Subject"
    )
    assert_not email.valid?
    assert_includes email.errors[:body], "can't be blank"
  end

  test "belongs to meeting" do
    email = follow_up_emails(:one)
    assert_instance_of Meeting, email.meeting
  end

  test "recipient_list splits comma-separated recipients" do
    email = FollowUpEmail.new(recipients: "alice@example.com, bob@example.com")
    assert_equal ["alice@example.com", "bob@example.com"], email.recipient_list
  end

  test "stores rich text body via Action Text" do
    email = follow_up_emails(:one)
    email.update!(body: "<h1>Follow-up</h1><p>Here are the action items...</p>")
    assert email.body.present?
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/models/follow_up_email_test.rb`
Expected: FAIL

**Step 3: Create the migration**

```ruby
# db/migrate/TIMESTAMP_create_follow_up_emails.rb
class CreateFollowUpEmails < ActiveRecord::Migration[8.1]
  def change
    create_table :follow_up_emails do |t|
      t.references :meeting, null: false, foreign_key: true
      t.string :recipients, null: false
      t.string :subject, null: false
      t.datetime :sent_at

      t.timestamps
    end
  end
end
```

**Step 4: Create the model**

```ruby
# app/models/follow_up_email.rb
class FollowUpEmail < ApplicationRecord
  belongs_to :meeting

  has_rich_text :body

  validates :recipients, presence: true
  validates :subject, presence: true
  validates :body, presence: true

  def recipient_list
    recipients.split(",").map(&:strip)
  end
end
```

**Step 5: Create fixtures**

```yaml
# test/fixtures/follow_up_emails.yml
one:
  meeting: one
  recipients: "alice@example.com, bob@example.com"
  subject: "Follow-up: Weekly Standup"
  sent_at: "2026-02-12 15:00:00"
```

Note: Rich text body for fixtures must be set up in test code. Assign body in tests:

```ruby
# In test setup or individual tests:
follow_up_emails(:one).update!(body: "Here is the meeting summary and action items...")
```

**Step 6: Run migration and tests**

Run: `bin/rails db:migrate && bin/rails test test/models/follow_up_email_test.rb`
Expected: All tests PASS

**Step 7: Commit**

```bash
git add -A && git commit -m "feat: add FollowUpEmail model with Action Text body for rich email content"
```

---

### Task 8: Meeting#check_processing_complete! Tests

**Files:**

- Modify: `test/models/meeting_test.rb`

**Step 1: Add integration tests for the completion check**

```ruby
# Add to test/models/meeting_test.rb

test "check_processing_complete! transitions to completed when summary and action items exist" do
  meeting = meetings(:one)
  meeting.update!(status: :processing)

  # Ensure summary has Action Text content (fixture has no rich text body)
  meeting.summary.update!(content: "Test summary") unless meeting.summary.content.present?

  # Meeting fixture :one already has summary and action_items fixtures
  meeting.check_processing_complete!

  assert_equal "completed", meeting.reload.status
end

test "check_processing_complete! does not transition when summary is missing" do
  meeting = meetings(:two)
  meeting.update!(status: :processing)

  # No summary or action items for meeting :two
  meeting.check_processing_complete!

  assert_equal "processing", meeting.reload.status
end

test "check_processing_complete! does not transition when action items are missing" do
  meeting = meetings(:two)
  meeting.update!(status: :processing)
  Summary.create!(meeting: meeting, content: "Test summary", model_used: "test")

  meeting.check_processing_complete!

  assert_equal "processing", meeting.reload.status
end
```

**Step 2: Run tests**

Run: `bin/rails test test/models/meeting_test.rb`
Expected: All tests PASS (model already has the method)

**Step 3: Commit**

```bash
git add -A && git commit -m "test: add Meeting#check_processing_complete! integration tests"
```
