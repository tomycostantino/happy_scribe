require "test_helper"

class HappyScribe::Transcription::StatusPollJobTest < ActiveJob::TestCase
  test "delegates to HappyScribe::Transcription::StatusPoll" do
    called_with = nil

    HappyScribe::Transcription::StatusPoll.stub(:perform_now, ->(id, poll_count:) { called_with = { id: id, poll_count: poll_count } }) do
      HappyScribe::Transcription::StatusPollJob.perform_now(42, poll_count: 5)
    end

    assert_equal({ id: 42, poll_count: 5 }, called_with)
  end
end
