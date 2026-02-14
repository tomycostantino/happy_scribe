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
