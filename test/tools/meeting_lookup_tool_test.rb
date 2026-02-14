require "test_helper"

class MeetingLookupToolTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @tool = MeetingLookupTool.new(@user)
  end

  test "finds meetings by title search" do
    result = @tool.execute(query: "Standup")
    assert_includes result, "Weekly Standup"
  end

  test "filters by date range" do
    result = @tool.execute(after: "2020-01-01", before: "2030-12-31")
    assert result.present?
    assert_includes result, "Weekly Standup"
  end

  test "filters by participant/speaker" do
    result = @tool.execute(participant: "Speaker 1")
    assert_includes result, "Weekly Standup"
  end

  test "scopes to current user only" do
    other_user = users(:two)
    Meeting.insert({ title: "Secret Meeting", language: "en-US", status: "completed", user_id: other_user.id, created_at: Time.current, updated_at: Time.current })

    result = @tool.execute(query: "Secret")
    refute_includes result, "Secret Meeting"
  end

  test "returns message when no meetings found" do
    result = @tool.execute(query: "NonexistentMeetingTitle12345")
    assert_includes result, "No meetings found"
  end

  test "excludes uploading and failed meetings" do
    result = @tool.execute(query: "Project Kickoff")
    refute_includes result, "Project Kickoff"  # status: uploading

    result = @tool.execute(query: "Failed Meeting")
    refute_includes result, "Failed Meeting"  # status: failed
  end

  test "has correct tool description" do
    assert_includes MeetingLookupTool.description, "meeting"
  end
end
