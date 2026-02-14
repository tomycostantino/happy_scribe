require "test_helper"

class MeetingSummaryToolTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @tool = MeetingSummaryTool.new(@user)
  end

  test "returns existing summary for a meeting" do
    meeting = meetings(:one)
    # Ensure clean state — destroy any existing summary first
    meeting.summary&.destroy
    summary = meeting.create_summary!(model_used: "test")
    summary.update!(content: "This was a productive meeting about Q3.")

    result = @tool.execute(meeting_id: meeting.id)
    assert_includes result, "productive meeting"
    assert_includes result, "Weekly Standup"
  end

  test "returns message when no summary exists" do
    meeting = meetings(:one)
    meeting.summary&.destroy

    result = @tool.execute(meeting_id: meeting.id)
    assert_includes result, "No summary"
  end

  test "raises RecordNotFound for other user's meeting" do
    other_user = users(:two)
    Meeting.insert({
      title: "Other", language: "en-US", status: "completed",
      user_id: other_user.id, created_at: Time.current, updated_at: Time.current
    })
    other_id = Meeting.where(user: other_user).last.id

    assert_raises(ActiveRecord::RecordNotFound) do
      @tool.execute(meeting_id: other_id)
    end
  end

  test "has correct tool description" do
    assert_includes MeetingSummaryTool.description, "summary"
  end
end
