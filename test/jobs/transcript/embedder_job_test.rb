require "test_helper"

class Transcript::EmbedderJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "delegates to Transcript::Embedder" do
    meeting = meetings(:one)
    meeting.transcript.transcript_chunks.delete_all

    Transcript::EmbedderJob.perform_now(meeting.id)

    assert meeting.transcript.transcript_chunks.reload.any?
  end

  test "job is enqueued on llm queue" do
    assert_equal "llm", Transcript::EmbedderJob.new.queue_name
  end
end
