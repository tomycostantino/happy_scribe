require "test_helper"
require "turbo/broadcastable/test_helper"

class Meeting::ActionItem::BroadcastableTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper

  setup do
    @meeting = meetings(:one)
    @item = @meeting.action_items.create!(description: "Test broadcast task", completed: false)
  end

  test "broadcasts replace to meeting stream when completed changes" do
    assert_turbo_stream_broadcasts @meeting, count: 1 do
      @item.update!(completed: true)
    end
  end

  test "does not broadcast when non-completion attributes change" do
    assert_no_turbo_stream_broadcasts @meeting do
      @item.update!(assignee: "New Person")
    end
  end

  test "broadcasts when toggled back to pending" do
    @item.update_column(:completed, true)

    assert_turbo_stream_broadcasts @meeting, count: 1 do
      @item.update!(completed: false)
    end
  end

  test "broadcasts replace action targeting the action items container" do
    streams = capture_turbo_stream_broadcasts @meeting do
      @item.update!(completed: true)
    end

    assert_equal 1, streams.size
    assert_equal "replace", streams.first["action"]
    assert_equal "meeting_#{@meeting.id}_action_items", streams.first["target"]
  end
end
