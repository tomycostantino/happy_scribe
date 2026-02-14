require "test_helper"

class Meeting::ActionItem::ExtractJobTest < ActiveJob::TestCase
  test "delegates to Meeting::ActionItem::Extract PORO" do
    meeting = meetings(:two)

    Meeting::ActionItem::Extract.stub(:perform_now, ->(id) { assert_equal meeting.id, id }) do
      Meeting::ActionItem::ExtractJob.perform_now(meeting.id)
    end
  end

  test "uses llm queue" do
    assert_equal "llm", Meeting::ActionItem::ExtractJob.new.queue_name
  end
end
