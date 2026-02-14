require "test_helper"

class CompleteActionItemToolTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @tool = CompleteActionItemTool.new(@user)
    @meeting = meetings(:one)
    @item = @meeting.action_items.create!(description: "Finish the report", assignee: "Sarah", completed: false)
  end

  test "marks a pending action item as done" do
    result = @tool.execute(action_item_id: @item.id)

    assert_includes result, "Finish the report"
    assert_includes result, "done"
    assert @item.reload.completed?
  end

  test "marks a done action item as pending (toggle)" do
    @item.update!(completed: true)

    result = @tool.execute(action_item_id: @item.id, completed: false)

    assert_includes result, "Finish the report"
    assert_includes result, "pending"
    refute @item.reload.completed?
  end

  test "defaults to marking as done when completed param omitted" do
    result = @tool.execute(action_item_id: @item.id)

    assert @item.reload.completed?
  end

  test "rejects access to another user's action item" do
    other_user = users(:two)
    Meeting.insert({
      title: "Private", language: "en-US", status: "completed",
      user_id: other_user.id, created_at: Time.current, updated_at: Time.current
    })
    other_meeting = Meeting.where(user: other_user).last
    other_item = other_meeting.action_items.create!(description: "Secret task")

    result = @tool.execute(action_item_id: other_item.id)

    assert_includes result, "not found"
    refute other_item.reload.completed?
  end

  test "handles non-existent action item" do
    result = @tool.execute(action_item_id: -1)

    assert_includes result, "not found"
  end

  test "can mark multiple items done by calling execute multiple times" do
    item2 = @meeting.action_items.create!(description: "Review slides", completed: false)

    @tool.execute(action_item_id: @item.id)
    @tool.execute(action_item_id: item2.id)

    assert @item.reload.completed?
    assert item2.reload.completed?
  end

  test "finds action item by description substring" do
    result = @tool.execute(description: "Finish the report", meeting_id: @meeting.id)

    assert_includes result, "done"
    assert @item.reload.completed?
  end

  test "finds action item by partial description match" do
    result = @tool.execute(description: "Finish", meeting_id: @meeting.id)

    assert_includes result, "done"
    assert @item.reload.completed?
  end

  test "description lookup is scoped to meeting when meeting_id provided" do
    other_item = @meeting.action_items.create!(description: "Finish the slides", completed: false)

    result = @tool.execute(description: "Finish the report", meeting_id: @meeting.id)

    assert @item.reload.completed?
    refute other_item.reload.completed?
  end

  test "returns not found when description matches nothing" do
    result = @tool.execute(description: "nonexistent task", meeting_id: @meeting.id)

    assert_includes result, "not found"
  end

  test "has correct tool description" do
    assert_includes CompleteActionItemTool.description.downcase, "action item"
  end
end
