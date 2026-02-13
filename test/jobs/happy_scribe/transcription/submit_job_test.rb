require "test_helper"

class HappyScribe::Transcription::SubmitJobTest < ActiveJob::TestCase
  test "delegates to HappyScribe::Transcription::Submit" do
    called_with = nil

    HappyScribe::Transcription::Submit.stub(:perform_now, ->(id) { called_with = id }) do
      HappyScribe::Transcription::SubmitJob.perform_now(42)
    end

    assert_equal 42, called_with
  end
end
