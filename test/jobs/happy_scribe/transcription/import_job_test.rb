require "test_helper"

class HappyScribe::Transcription::ImportJobTest < ActiveJob::TestCase
  test "delegates to HappyScribe::Transcription::Import" do
    called_with = nil

    HappyScribe::Transcription::Import.stub(:perform_now, ->(user_id, happyscribe_id:) { called_with = [ user_id, happyscribe_id ] }) do
      HappyScribe::Transcription::ImportJob.perform_now(42, happyscribe_id: "hs_123")
    end

    assert_equal [ 42, "hs_123" ], called_with
  end
end
