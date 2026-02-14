# Meeting Participants Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Link contacts to meetings via a `Meeting::Participant` join model so we can identify which contacts were in a meeting, map them to transcript speakers, and email them relevant data.

**Architecture:** A new `meeting_participants` join table connects `meetings` to `contacts` with an optional `role` enum and a `speaker_label` string that maps to `transcript_segments.speaker`. Associations are added to `Meeting`, `Contact`, and the new `Meeting::Participant` model. A `#segments` method on the participant provides access to that person's transcript segments.

**Tech Stack:** Rails 8.1, PostgreSQL, Minitest

---

### Task 1: Migration — Create `meeting_participants` Table

**Files:**
- Create: `db/migrate/TIMESTAMP_create_meeting_participants.rb`

**Step 1: Generate the migration**

Run:
```bash
bin/rails generate migration CreateMeetingParticipants meeting:references contact:references role:string speaker_label:string
```

**Step 2: Edit the migration to add constraints and indexes**

Replace the generated migration body with:

```ruby
class CreateMeetingParticipants < ActiveRecord::Migration[8.1]
  def change
    create_table :meeting_participants do |t|
      t.references :meeting, null: false, foreign_key: true
      t.references :contact, null: false, foreign_key: true
      t.string :role, default: "attendee"
      t.string :speaker_label

      t.timestamps
    end

    add_index :meeting_participants, [:meeting_id, :contact_id], unique: true
  end
end
```

**Step 3: Run the migration**

Run: `bin/rails db:migrate`
Expected: Migration runs successfully, `meeting_participants` table appears in `db/schema.rb`.

**Step 4: Commit**

```bash
git add db/migrate/*_create_meeting_participants.rb db/schema.rb
git commit -m "feat: add meeting_participants join table"
```

---

### Task 2: Model — `Meeting::Participant`

**Files:**
- Create: `app/models/meeting/participant.rb`
- Create: `test/models/meeting/participant_test.rb`
- Create: `test/fixtures/meeting/participants.yml`

**Step 1: Create the fixture file**

Create `test/fixtures/meeting/participants.yml`:

```yaml
sarah_in_standup:
  meeting: one
  contact: sarah
  role: "organizer"
  speaker_label: "Speaker 1"

tom_in_standup:
  meeting: one
  contact: tom
  role: "attendee"
  speaker_label: "Speaker 2"
```

These map the existing contacts (sarah, tom) to meeting :one, and tie them to the existing transcript_segments fixtures where Speaker 1 and Speaker 2 are used.

**Step 2: Write the failing tests**

Create `test/models/meeting/participant_test.rb`:

```ruby
require "test_helper"

class Meeting::ParticipantTest < ActiveSupport::TestCase
  test "valid participant with meeting and contact" do
    participant = Meeting::Participant.new(
      meeting: meetings(:one),
      contact: contacts(:sarah)
    )
    assert participant.valid?
  end

  test "requires a meeting" do
    participant = Meeting::Participant.new(contact: contacts(:sarah))
    assert_not participant.valid?
    assert_includes participant.errors[:meeting], "must exist"
  end

  test "requires a contact" do
    participant = Meeting::Participant.new(meeting: meetings(:one))
    assert_not participant.valid?
    assert_includes participant.errors[:contact], "must exist"
  end

  test "enforces unique contact per meeting" do
    assert_no_difference "Meeting::Participant.count" do
      duplicate = Meeting::Participant.new(
        meeting: meetings(:one),
        contact: contacts(:sarah)
      )
      assert_not duplicate.valid?
      assert_includes duplicate.errors[:contact_id], "has already been taken"
    end
  end

  test "defaults role to attendee" do
    participant = Meeting::Participant.new
    assert_equal "attendee", participant.role
  end

  test "role can be set to organizer" do
    participant = meeting_participants(:sarah_in_standup)
    assert_equal "organizer", participant.role
  end

  test "segments returns transcript segments matching speaker_label" do
    participant = meeting_participants(:sarah_in_standup)
    segments = participant.segments

    assert_equal 2, segments.count
    assert segments.all? { |s| s.speaker == "Speaker 1" }
  end

  test "segments returns none when speaker_label is blank" do
    participant = Meeting::Participant.new(
      meeting: meetings(:one),
      contact: contacts(:sarah),
      speaker_label: nil
    )
    assert_empty participant.segments
  end

  test "segments returns none when meeting has no transcript" do
    participant = Meeting::Participant.new(
      meeting: meetings(:two),
      contact: contacts(:sarah),
      speaker_label: "Speaker 1"
    )
    assert_empty participant.segments
  end
end
```

**Step 3: Run tests to verify they fail**

Run: `bin/rails test test/models/meeting/participant_test.rb`
Expected: All tests fail (model doesn't exist yet).

**Step 4: Write the model**

Create `app/models/meeting/participant.rb`:

```ruby
class Meeting::Participant < ApplicationRecord
  belongs_to :meeting
  belongs_to :contact

  validates :contact_id, uniqueness: { scope: :meeting_id }

  enum :role, {
    attendee: "attendee",
    organizer: "organizer"
  }, default: :attendee

  def segments
    return TranscriptSegment.none if speaker_label.blank?

    transcript = meeting.transcript
    return TranscriptSegment.none if transcript.nil?

    transcript.transcript_segments.where(speaker: speaker_label).ordered
  end
end
```

**Step 5: Run tests to verify they pass**

Run: `bin/rails test test/models/meeting/participant_test.rb`
Expected: All tests pass.

**Step 6: Commit**

```bash
git add app/models/meeting/participant.rb test/models/meeting/participant_test.rb test/fixtures/meeting/participants.yml
git commit -m "feat: add Meeting::Participant model with speaker_label mapping"
```

---

### Task 3: Associations — Update Meeting and Contact

**Files:**
- Modify: `app/models/meeting.rb`
- Modify: `app/models/contact.rb`
- Create: `test/models/meeting/participant_associations_test.rb`

**Step 1: Write the failing tests**

Create `test/models/meeting/participant_associations_test.rb`:

```ruby
require "test_helper"

class Meeting::ParticipantAssociationsTest < ActiveSupport::TestCase
  test "meeting has many participants" do
    meeting = meetings(:one)
    assert_equal 2, meeting.participants.count
  end

  test "meeting has many contacts through participants" do
    meeting = meetings(:one)
    assert_includes meeting.contacts, contacts(:sarah)
    assert_includes meeting.contacts, contacts(:tom)
  end

  test "contact has many meeting_participants" do
    sarah = contacts(:sarah)
    assert_equal 1, sarah.meeting_participants.count
  end

  test "contact has many meetings through meeting_participants" do
    sarah = contacts(:sarah)
    assert_includes sarah.meetings, meetings(:one)
  end

  test "destroying a meeting destroys its participants" do
    meeting = meetings(:one)
    assert_difference "Meeting::Participant.count", -2 do
      meeting.destroy
    end
  end

  test "destroying a contact destroys its meeting_participants" do
    sarah = contacts(:sarah)
    assert_difference "Meeting::Participant.count", -1 do
      sarah.destroy
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/models/meeting/participant_associations_test.rb`
Expected: Tests fail (associations not defined yet).

**Step 3: Add associations to Meeting**

In `app/models/meeting.rb`, add after the `has_many :follow_up_emails` line:

```ruby
has_many :participants, class_name: "Meeting::Participant", dependent: :destroy
has_many :contacts, through: :participants
```

**Step 4: Add associations to Contact**

In `app/models/contact.rb`, add after `belongs_to :user`:

```ruby
has_many :meeting_participants, class_name: "Meeting::Participant", dependent: :destroy
has_many :meetings, through: :meeting_participants
```

**Step 5: Run tests to verify they pass**

Run: `bin/rails test test/models/meeting/participant_associations_test.rb`
Expected: All tests pass.

**Step 6: Run full test suite to check for regressions**

Run: `bin/rails test`
Expected: All existing tests still pass.

**Step 7: Commit**

```bash
git add app/models/meeting.rb app/models/contact.rb test/models/meeting/participant_associations_test.rb
git commit -m "feat: add participant associations to Meeting and Contact"
```

---

## Summary of Changes

| File | Action |
|------|--------|
| `db/migrate/TIMESTAMP_create_meeting_participants.rb` | Create |
| `app/models/meeting/participant.rb` | Create |
| `app/models/meeting.rb` | Add 2 lines (associations) |
| `app/models/contact.rb` | Add 2 lines (associations) |
| `test/fixtures/meeting/participants.yml` | Create |
| `test/models/meeting/participant_test.rb` | Create |
| `test/models/meeting/participant_associations_test.rb` | Create |

## What This Enables (Future Work)

- **UI:** "Add participant" button on meeting show page, participant list with speaker assignment
- **AI matching:** After transcription, AI suggests mapping speaker labels to contacts
- **Personalized emails:** Query `participant.segments` and matching action items to compose per-contact emails
- **Contact page:** Show all meetings a contact participated in
- **Calendar import:** When Google Calendar integration lands, map attendees to participants automatically
