require "test_helper"

class HappyScribe::ImportsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    sign_in_as(users(:one))
  end

  test "index requires authentication" do
    sign_out
    get happy_scribe_imports_url
    assert_redirected_to new_session_url
  end

  test "index lists transcriptions from HappyScribe" do
    mock_client = Minitest::Mock.new
    mock_client.expect(:list_transcriptions, {
      "results" => [
        { "id" => "hs_1", "name" => "Meeting 1", "state" => "automatic_done", "createdAt" => "2026-01-15T10:00:00.000+00:00", "audioLengthInSeconds" => 120 },
        { "id" => "hs_2", "name" => "Meeting 2", "state" => "automatic_done", "createdAt" => "2026-01-16T10:00:00.000+00:00", "audioLengthInSeconds" => 60 }
      ],
      "_links" => {}
    }, page: nil)

    HappyScribe::Client.stub(:new, mock_client) do
      get happy_scribe_imports_url
    end

    assert_response :success
    assert_match "Meeting 1", response.body
    assert_match "Meeting 2", response.body
    mock_client.verify
  end

  test "index marks already-imported transcriptions" do
    mock_client = Minitest::Mock.new
    mock_client.expect(:list_transcriptions, {
      "results" => [
        { "id" => "hs_transcript_001", "name" => "Already Imported", "state" => "automatic_done", "createdAt" => "2026-01-15T10:00:00.000+00:00" }
      ],
      "_links" => {}
    }, page: nil)

    HappyScribe::Client.stub(:new, mock_client) do
      get happy_scribe_imports_url
    end

    assert_response :success
    assert_match "Imported", response.body
    mock_client.verify
  end

  test "index handles API errors gracefully" do
    mock_client = Minitest::Mock.new
    mock_client.expect(:list_transcriptions, nil) do
      raise HappyScribe::ApiError.new("API down", status: 500)
    end

    HappyScribe::Client.stub(:new, mock_client) do
      get happy_scribe_imports_url
    end

    assert_response :success
    assert_match "Could not load transcriptions", response.body
  end

  test "create enqueues import job" do
    assert_enqueued_with(job: HappyScribe::Transcription::ImportJob) do
      post happy_scribe_imports_url, params: { happyscribe_id: "hs_new_123" }
    end

    assert_redirected_to meetings_url
    assert_equal "Import started. The transcription will appear shortly.", flash[:notice]
  end

  test "create rejects already-imported transcription" do
    post happy_scribe_imports_url, params: { happyscribe_id: "hs_transcript_001" }

    assert_redirected_to happy_scribe_imports_url
    assert_equal "This transcription has already been imported.", flash[:alert]
  end

  test "create requires authentication" do
    sign_out
    post happy_scribe_imports_url, params: { happyscribe_id: "hs_123" }
    assert_redirected_to new_session_url
  end
end
