require "test_helper"

class HappyScribe::PollTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @meeting = meetings(:two)
    @meeting.update!(status: :transcribing)
    @transcript = transcripts(:two)
    @transcript.update!(happyscribe_id: "hs_poll", status: :processing)
  end

  test "creates export when transcription is done" do
    mock_client = Minitest::Mock.new
    mock_client.expect(:retrieve_transcription, { "id" => "hs_poll", "state" => "automatic_done", "audioLengthInSeconds" => 120 }, id: "hs_poll")
    mock_client.expect(:create_export, { "id" => "exp_001", "state" => "pending" },
      transcription_ids: [ "hs_poll" ], format: "json", show_speakers: true)

    HappyScribe::Client.stub(:new, mock_client) do
      assert_enqueued_with(job: FetchExportJob) do
        HappyScribe::Poll.perform_now(@meeting.id)
      end
    end

    assert_equal "exp_001", @transcript.reload.happyscribe_export_id
    assert_equal 120, @transcript.audio_length_seconds
    mock_client.verify
  end

  test "re-enqueues when still processing" do
    mock_client = Minitest::Mock.new
    mock_client.expect(:retrieve_transcription, { "id" => "hs_poll", "state" => "automatic_transcribing" }, id: "hs_poll")

    HappyScribe::Client.stub(:new, mock_client) do
      assert_enqueued_with(job: PollTranscriptionJob) do
        HappyScribe::Poll.perform_now(@meeting.id, poll_count: 0)
      end
    end

    assert_equal "transcribing", @meeting.reload.status
    mock_client.verify
  end

  test "marks as failed when transcription fails" do
    mock_client = Minitest::Mock.new
    mock_client.expect(:retrieve_transcription, { "id" => "hs_poll", "state" => "failed" }, id: "hs_poll")

    HappyScribe::Client.stub(:new, mock_client) do
      HappyScribe::Poll.perform_now(@meeting.id)
    end

    assert_equal "failed", @meeting.reload.status
    assert_equal "failed", @transcript.reload.status
    mock_client.verify
  end

  test "gives up after max polls" do
    mock_client = Minitest::Mock.new
    mock_client.expect(:retrieve_transcription, { "id" => "hs_poll", "state" => "automatic_transcribing" }, id: "hs_poll")

    HappyScribe::Client.stub(:new, mock_client) do
      HappyScribe::Poll.perform_now(@meeting.id, poll_count: 360)
    end

    assert_equal "failed", @meeting.reload.status
    mock_client.verify
  end
end
