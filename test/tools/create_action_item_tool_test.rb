require "test_helper"

class CreateActionItemToolTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @tool = CreateActionItemTool.new(@user)
    @meeting = meetings(:one)
    @meeting.action_items.destroy_all
  end

  test "creates an action item for a valid meeting" do
    result = @tool.execute(meeting_id: @meeting.id, description: "Review the budget proposal")

    assert_includes result, "Review the budget proposal"
    assert @meeting.action_items.exists?(description: "Review the budget proposal")
  end

  test "creates an action item with assignee and due date" do
    result = @tool.execute(
      meeting_id: @meeting.id,
      description: "Prepare slides",
      assignee: "Alice",
      due_date: "2026-03-01"
    )

    item = @meeting.action_items.find_by(description: "Prepare slides")
    assert item.present?
    assert_equal "Alice", item.assignee
    assert_equal Date.new(2026, 3, 1), item.due_date
    assert_includes result, "Prepare slides"
    assert_includes result, "Alice"
    assert_includes result, "2026-03-01"
  end

  test "strips whitespace from description and assignee" do
    @tool.execute(meeting_id: @meeting.id, description: "  Trim me  ", assignee: "  Bob  ")

    item = @meeting.action_items.reload.find_by(description: "Trim me")
    assert item.present?, "Expected action item with stripped description"
    assert_equal "Bob", item.assignee
  end

  test "rejects access to another user's meeting" do
    other_user = users(:two)
    Meeting.insert({
      title: "Private Meeting", language: "en-US", status: "completed",
      user_id: other_user.id, created_at: Time.current, updated_at: Time.current
    })
    other_meeting_id = Meeting.where(user: other_user).last.id

    result = @tool.execute(meeting_id: other_meeting_id, description: "Sneak in")
    assert_includes result, "Meeting not found"
    refute Meeting::ActionItem.exists?(description: "Sneak in")
  end

  test "skips duplicate action items with case-insensitive match" do
    @meeting.action_items.create!(description: "Send the report")

    result = @tool.execute(meeting_id: @meeting.id, description: "send the report")
    assert_includes result, "already exists"
    assert_equal 1, @meeting.action_items.where("description ILIKE ?", "send the report").count
  end

  test "handles invalid due date gracefully" do
    result = @tool.execute(meeting_id: @meeting.id, description: "Do something", due_date: "not-a-date")
    assert_includes result, "Invalid due date"
    refute @meeting.action_items.exists?(description: "Do something")
  end

  test "handles missing description" do
    result = @tool.execute(meeting_id: @meeting.id, description: "")
    assert_includes result, "Failed to create"
  end

  test "saves nil when assignee is blank string" do
    @tool.execute(meeting_id: @meeting.id, description: "Blank assignee task", assignee: "")

    item = @meeting.action_items.find_by(description: "Blank assignee task")
    assert item.present?
    assert_nil item.assignee
  end

  test "creates action item without optional fields" do
    result = @tool.execute(meeting_id: @meeting.id, description: "Simple task")

    item = @meeting.action_items.find_by(description: "Simple task")
    assert item.present?
    assert_nil item.assignee
    assert_nil item.due_date
    assert_equal false, item.completed
  end

  test "has correct tool description" do
    assert_includes CreateActionItemTool.description.downcase, "action item"
  end

  test "has button_label for quick-action UI" do
    assert_equal "Extract & save action items", CreateActionItemTool.button_label
  end

  test "has button_prompt for quick-action UI" do
    prompt = CreateActionItemTool.button_prompt
    assert prompt.present?
    assert_includes prompt.downcase, "action item"
  end
end
