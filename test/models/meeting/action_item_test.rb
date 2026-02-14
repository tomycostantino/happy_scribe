require "test_helper"

class Meeting::ActionItemTest < ActiveSupport::TestCase
  test "valid action item" do
    item = Meeting::ActionItem.new(meeting: meetings(:one), description: "Send the Q3 report")
    assert item.valid?
  end

  test "requires description" do
    item = Meeting::ActionItem.new(meeting: meetings(:one))
    assert_not item.valid?
    assert_includes item.errors[:description], "can't be blank"
  end

  test "requires a meeting" do
    item = Meeting::ActionItem.new(description: "Do something")
    assert_not item.valid?
  end

  test "defaults completed to false" do
    item = Meeting::ActionItem.new
    assert_equal false, item.completed
  end

  test "scopes: pending and done" do
    meeting = meetings(:one)
    pending_item = meeting.action_items.create!(description: "Pending task", completed: false)
    done_item = meeting.action_items.create!(description: "Done task", completed: true)

    assert_includes Meeting::ActionItem.pending, pending_item
    assert_not_includes Meeting::ActionItem.pending, done_item
    assert_includes Meeting::ActionItem.done, done_item
  end
end
