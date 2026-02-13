require "test_helper"

class SubmitTranscriptionJobTest < ActiveJob::TestCase
  test "delegates to HappyScribe::Submission" do
    called_with = nil

    HappyScribe::Submission.stub(:perform_now, ->(id) { called_with = id }) do
      SubmitTranscriptionJob.perform_now(42)
    end

    assert_equal 42, called_with
  end
end
