require "test_helper"

class PollTranscriptionJobTest < ActiveJob::TestCase
  test "delegates to HappyScribe::Poll" do
    called_with = nil

    HappyScribe::Poll.stub(:perform_now, ->(id, poll_count:) { called_with = { id: id, poll_count: poll_count } }) do
      PollTranscriptionJob.perform_now(42, poll_count: 5)
    end

    assert_equal({ id: 42, poll_count: 5 }, called_with)
  end
end
