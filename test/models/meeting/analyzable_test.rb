require "test_helper"

class Meeting::AnalyzableTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "enqueues AI processing jobs when start_analysis! is called" do
    meeting = meetings(:one)
    meeting.update_column(:status, "transcribed")

    assert_enqueued_jobs 3 do
      meeting.start_analysis!
    end

    assert_enqueued_with(job: Meeting::Summary::GenerateJob, args: [ meeting.id ])
    assert_enqueued_with(job: Meeting::ActionItem::ExtractJob, args: [ meeting.id ])
    assert_enqueued_with(job: Transcript::EmbedderJob, args: [ meeting.id ])
  end

  test "transitions meeting to processing status" do
    meeting = meetings(:one)
    meeting.update_column(:status, "transcribed")

    meeting.start_analysis!

    assert_equal "processing", meeting.reload.status
  end

  test "does not enqueue if already processing" do
    meeting = meetings(:one)
    meeting.update_column(:status, "processing")

    assert_no_enqueued_jobs do
      meeting.start_analysis!
    end
  end

  test "does not enqueue if already completed" do
    meeting = meetings(:one)
    meeting.update_column(:status, "completed")

    assert_no_enqueued_jobs do
      meeting.start_analysis!
    end
  end

  test "does not enqueue if failed" do
    meeting = meetings(:failed)

    assert_no_enqueued_jobs do
      meeting.start_analysis!
    end
  end
end
