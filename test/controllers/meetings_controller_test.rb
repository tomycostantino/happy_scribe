require "test_helper"

class MeetingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
  end

  test "index shows user's meetings" do
    get meetings_url
    assert_response :success
  end

  test "index requires authentication" do
    sign_out
    get meetings_url
    assert_redirected_to new_session_url
  end

  test "show displays meeting" do
    get meeting_url(meetings(:one))
    assert_response :success
  end

  test "show scopes to current user" do
    sign_in_as(users(:two))
    get meeting_url(meetings(:one))
    assert_response :not_found
  end

  test "new shows form" do
    get new_meeting_url
    assert_response :success
  end

  test "create with valid params creates meeting and enqueues job" do
    file = fixture_file_upload("test/fixtures/files/sample.mp3", "audio/mpeg")

    assert_difference("Meeting.count") do
      assert_difference("Transcript.count") do
        assert_enqueued_with(job: HappyScribe::Transcription::SubmitJob) do
          post meetings_url, params: {
            meeting: { title: "New Meeting", language: "en-US", recording: file }
          }
        end
      end
    end

    meeting = Meeting.last
    assert_equal "uploading", meeting.status
    assert meeting.recording.attached?
    assert_redirected_to meeting_url(meeting)
  end

  test "create without title fails" do
    file = fixture_file_upload("test/fixtures/files/sample.mp3", "audio/mpeg")

    assert_no_difference("Meeting.count") do
      post meetings_url, params: {
        meeting: { title: "", language: "en-US", recording: file }
      }
    end
    assert_response :unprocessable_entity
  end

  test "create without file fails" do
    assert_no_difference("Meeting.count") do
      post meetings_url, params: {
        meeting: { title: "Test", language: "en-US" }
      }
    end
    assert_response :unprocessable_entity
  end

  test "destroy removes meeting" do
    assert_difference("Meeting.count", -1) do
      delete meeting_url(meetings(:two))
    end
    assert_redirected_to meetings_url
  end
end
