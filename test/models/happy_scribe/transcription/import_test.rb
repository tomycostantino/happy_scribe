require "test_helper"

class HappyScribe::Transcription::ImportTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:one)
  end

  test "imports a completed transcription from HappyScribe" do
    mock_client = Minitest::Mock.new
    mock_client.expect(:retrieve_transcription, {
      "id" => "hs_import_123",
      "name" => "Imported Meeting",
      "state" => "automatic_done",
      "language" => "en-GB",
      "audioLengthInSeconds" => 300
    }, id: "hs_import_123")

    mock_client.expect(:create_export, {
      "id" => "exp_import_123",
      "state" => "pending"
    }, transcription_ids: [ "hs_import_123" ], format: "json", show_speakers: true)

    HappyScribe::Client.stub(:new, mock_client) do
      assert_difference("Meeting.count") do
        assert_difference("Transcript.count") do
          assert_enqueued_with(job: HappyScribe::Transcription::ExportFetchJob) do
            meeting = HappyScribe::Transcription::Import.perform_now(@user.id, happyscribe_id: "hs_import_123")

            assert_equal "Imported Meeting", meeting.title
            assert_equal "en-GB", meeting.language
            assert_equal "imported", meeting.source
            assert_equal "transcribing", meeting.status
            assert_not meeting.recording.attached?

            transcript = meeting.transcript
            assert_equal "hs_import_123", transcript.happyscribe_id
            assert_equal "exp_import_123", transcript.happyscribe_export_id
            assert_equal 300, transcript.audio_length_seconds
            assert_equal "processing", transcript.status
          end
        end
      end
    end

    mock_client.verify
  end

  test "raises error when transcription is not ready" do
    mock_client = Minitest::Mock.new
    mock_client.expect(:retrieve_transcription, {
      "id" => "hs_pending",
      "name" => "Pending Meeting",
      "state" => "automatic_transcribing",
      "language" => "en-US"
    }, id: "hs_pending")

    HappyScribe::Client.stub(:new, mock_client) do
      assert_no_difference("Meeting.count") do
        assert_raises(HappyScribe::ApiError) do
          HappyScribe::Transcription::Import.perform_now(@user.id, happyscribe_id: "hs_pending")
        end
      end
    end

    mock_client.verify
  end

  test "re-raises rate limit errors" do
    mock_client = Minitest::Mock.new
    mock_client.expect(:retrieve_transcription, nil) do
      raise HappyScribe::RateLimitError.new("Rate limited", status: 429, retry_in: 30)
    end

    HappyScribe::Client.stub(:new, mock_client) do
      assert_raises(HappyScribe::RateLimitError) do
        HappyScribe::Transcription::Import.perform_now(@user.id, happyscribe_id: "hs_rate_limited")
      end
    end
  end

  test "defaults language to en-US when not provided" do
    mock_client = Minitest::Mock.new
    mock_client.expect(:retrieve_transcription, {
      "id" => "hs_no_lang",
      "name" => "No Language Meeting",
      "state" => "automatic_done",
      "language" => nil,
      "audioLengthInSeconds" => 60
    }, id: "hs_no_lang")

    mock_client.expect(:create_export, {
      "id" => "exp_no_lang",
      "state" => "pending"
    }, transcription_ids: [ "hs_no_lang" ], format: "json", show_speakers: true)

    HappyScribe::Client.stub(:new, mock_client) do
      meeting = HappyScribe::Transcription::Import.perform_now(@user.id, happyscribe_id: "hs_no_lang")
      assert_equal "en-US", meeting.language
    end

    mock_client.verify
  end
end
