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
