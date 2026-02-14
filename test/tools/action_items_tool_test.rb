require "test_helper"

class ActionItemsToolTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @tool = ActionItemsTool.new(@user)

    @meeting = meetings(:one)
    # Clear any existing action items from fixtures or prior tests
    @meeting.action_items.destroy_all
    @meeting.action_items.create!(description: "Send the Q3 report", assignee: "Sarah", completed: false)
    @meeting.action_items.create!(description: "Schedule follow-up meeting", assignee: "Tom", due_date: "2026-02-19", completed: false)
  end

  test "lists all action items for user" do
    result = @tool.execute
    assert_includes result, "Send the Q3 report"
    assert_includes result, "Schedule follow-up meeting"
  end

  test "filters by assignee" do
    result = @tool.execute(assignee: "Sarah")
    assert_includes result, "Send the Q3 report"
    refute_includes result, "Schedule follow-up meeting"
  end

  test "filters by completion status" do
    @meeting.action_items.find_by(assignee: "Sarah").update!(completed: true)

    result = @tool.execute(completed: false)
    refute_includes result, "Send the Q3 report"
    assert_includes result, "Schedule follow-up meeting"
  end

  test "filters by meeting_id" do
    # Insert directly to avoid validation (meeting doesn't have recording attached)
    failed_meeting = meetings(:failed)
    Meeting::ActionItem.insert({
      meeting_id: failed_meeting.id, description: "Other meeting task",
      completed: false, created_at: Time.current, updated_at: Time.current
    })

    result = @tool.execute(meeting_id: @meeting.id)
    assert_includes result, "Send the Q3 report"
    refute_includes result, "Other meeting task"
  end

  test "scopes to current user only" do
    other_user = users(:two)
    # Insert without validation since we don't have a recording
    Meeting.insert({
      title: "Other User Meeting", language: "en-US", status: "completed",
      user_id: other_user.id, created_at: Time.current, updated_at: Time.current
    })
    other_meeting = Meeting.where(user: other_user).last
    Meeting::ActionItem.insert({
      meeting_id: other_meeting.id, description: "Secret task",
      completed: false, created_at: Time.current, updated_at: Time.current
    })

    result = @tool.execute
    refute_includes result, "Secret task"
  end

  test "returns message when no action items found" do
    @meeting.action_items.destroy_all
    result = @tool.execute
    assert_includes result, "No action items found"
  end

  test "has correct tool description" do
    assert_includes ActionItemsTool.description, "action item"
  end
end
