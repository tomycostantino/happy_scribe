require "test_helper"

class Meeting::Summary::GenerateJobTest < ActiveJob::TestCase
  test "delegates to Meeting::Summary::Generate PORO" do
    meeting = meetings(:two)

    Meeting::Summary::Generate.stub(:perform_now, ->(id) { assert_equal meeting.id, id }) do
      Meeting::Summary::GenerateJob.perform_now(meeting.id)
    end
  end

  test "uses llm queue" do
    assert_equal "llm", Meeting::Summary::GenerateJob.new.queue_name
  end
end
