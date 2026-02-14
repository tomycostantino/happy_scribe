require "test_helper"

class HappyScribe::Transcription::ExportFetchTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @meeting = meetings(:two)
    @meeting.recording.attach(
      io: File.open(Rails.root.join("test/fixtures/files/sample.mp3")),
      filename: "sample.mp3",
      content_type: "audio/mpeg"
    )
    @meeting.update!(status: :transcribing)
    @transcript = transcripts(:two)
    @transcript.update!(happyscribe_id: "hs_fetch", happyscribe_export_id: "exp_fetch", status: :processing)
  end

  test "downloads and parses export when ready" do
    mock_client = Minitest::Mock.new
    mock_client.expect(:retrieve_export, {
      "id" => "exp_fetch", "state" => "ready", "download_link" => "https://cdn.example.com/export.json"
    }, id: "exp_fetch")

    export_json = [
      { "speaker" => "Speaker 1", "data_start" => 0.0, "data_end" => 2.0,
        "words" => [ { "text" => "Hello.", "data_start" => 0.0, "data_end" => 2.0 } ] },
      { "speaker" => "Speaker 2", "data_start" => 3.0, "data_end" => 4.0,
        "words" => [ { "text" => "Hi.", "data_start" => 3.0, "data_end" => 4.0 } ] }
    ].to_json

    mock_client.expect(:download, export_json, [ "https://cdn.example.com/export.json" ])

    HappyScribe::Client.stub(:new, mock_client) do
      assert_enqueued_jobs 3 do
        HappyScribe::Transcription::ExportFetch.perform_now(@meeting.id)
      end
    end

    assert_equal "completed", @transcript.reload.status
    assert_equal "processing", @meeting.reload.status
    assert_equal 2, @transcript.transcript_segments.count

    assert_enqueued_with(job: Meeting::Summary::GenerateJob, args: [ @meeting.id ])
    assert_enqueued_with(job: Meeting::ActionItem::ExtractJob, args: [ @meeting.id ])
    assert_enqueued_with(job: Transcript::EmbedderJob, args: [ @meeting.id ])

    mock_client.verify
  end

  test "re-enqueues when still processing" do
    mock_client = Minitest::Mock.new
    mock_client.expect(:retrieve_export, { "id" => "exp_fetch", "state" => "processing" }, id: "exp_fetch")

    HappyScribe::Client.stub(:new, mock_client) do
      assert_enqueued_with(job: HappyScribe::Transcription::ExportFetchJob) do
        HappyScribe::Transcription::ExportFetch.perform_now(@meeting.id, poll_count: 0)
      end
    end
    mock_client.verify
  end

  test "marks as failed when export fails" do
    mock_client = Minitest::Mock.new
    mock_client.expect(:retrieve_export, { "id" => "exp_fetch", "state" => "failed" }, id: "exp_fetch")

    HappyScribe::Client.stub(:new, mock_client) do
      HappyScribe::Transcription::ExportFetch.perform_now(@meeting.id)
    end

    assert_equal "failed", @meeting.reload.status
    mock_client.verify
  end
end
