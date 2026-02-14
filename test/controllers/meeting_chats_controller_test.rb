require "test_helper"

class MeetingChatsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
    @meeting = meetings(:one)
  end

  test "index shows meeting chats" do
    get meeting_chats_url(@meeting)
    assert_response :success
  end

  test "index requires authentication" do
    sign_out
    get meeting_chats_url(@meeting)
    assert_redirected_to new_session_url
  end

  test "index scopes to current user's meetings" do
    sign_in_as(users(:two))
    get meeting_chats_url(@meeting)
    assert_response :not_found
  end

  test "create starts new chat" do
    assert_difference("Chat.count") do
      post meeting_chats_url(@meeting)
    end
    assert_redirected_to meeting_chat_url(@meeting, Chat.last)
  end

  test "create with prompt enqueues ChatResponseJob" do
    assert_enqueued_with(job: ChatResponseJob) do
      post meeting_chats_url(@meeting), params: { prompt: "Summarize this meeting" }
    end
  end

  test "create without prompt does not enqueue job" do
    assert_no_enqueued_jobs(only: ChatResponseJob) do
      post meeting_chats_url(@meeting)
    end
  end

  test "show displays chat" do
    get meeting_chat_url(@meeting, chats(:meeting_chat))
    assert_response :success
  end

  test "show scopes chat to current user" do
    sign_in_as(users(:two))
    get meeting_chat_url(@meeting, chats(:meeting_chat))
    assert_response :not_found
  end
end
