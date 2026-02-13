require "test_helper"

class HappyScribe::SubmissionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @meeting = meetings(:two)
    @transcript = transcripts(:two)
    @meeting.recording.attach(
      io: StringIO.new("fake audio data"),
      filename: "meeting.mp3",
      content_type: "audio/mpeg"
    )
  end

  test "uploads file and creates transcription" do
    mock_client = Minitest::Mock.new
    mock_client.expect(:get_signed_upload_url, { "signedUrl" => "https://s3.example.com/signed" }, filename: "meeting.mp3")
    mock_client.expect(:upload_to_signed_url, true, signed_url: "https://s3.example.com/signed", file_data: "fake audio data", content_type: "audio/mpeg")
    mock_client.expect(:create_transcription, { "id" => "hs_123", "state" => "ingesting" },
      name: "Project Kickoff", language: "en-US", tmp_url: "https://s3.example.com/signed")

    HappyScribe::Client.stub(:new, mock_client) do
      assert_enqueued_with(job: PollTranscriptionJob) do
        HappyScribe::Submission.perform_now(@meeting.id)
      end
    end

    assert_equal "transcribing", @meeting.reload.status
    assert_equal "hs_123", @transcript.reload.happyscribe_id
    assert_equal "processing", @transcript.status
    mock_client.verify
  end

  test "marks meeting as failed on error" do
    mock_client = Minitest::Mock.new
    mock_client.expect(:get_signed_upload_url, nil) { raise HappyScribe::ApiError.new("fail", status: 500) }

    HappyScribe::Client.stub(:new, mock_client) do
      HappyScribe::Submission.perform_now(@meeting.id)
    end

    assert_equal "failed", @meeting.reload.status
  end
end
