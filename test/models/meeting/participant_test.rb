require "test_helper"

class Meeting::ParticipantTest < ActiveSupport::TestCase
  test "valid participant with meeting and contact" do
    contact = Contact.create!(name: "Jane Doe", email: "jane@example.com", user: users(:one))
    participant = Meeting::Participant.new(
      meeting: meetings(:one),
      contact: contact
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
