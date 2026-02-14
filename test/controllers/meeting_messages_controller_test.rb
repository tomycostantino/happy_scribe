require "test_helper"

class MeetingMessagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
    @meeting = meetings(:one)
    @chat = chats(:meeting_chat)
  end

  test "create enqueues ChatResponseJob" do
    assert_enqueued_with(job: ChatResponseJob) do
      post meeting_chat_messages_url(@meeting, @chat),
        params: { message: { content: "What was decided?" } }
    end
  end

  test "create with turbo stream format" do
    assert_enqueued_with(job: ChatResponseJob) do
      post meeting_chat_messages_url(@meeting, @chat),
        params: { message: { content: "What was decided?" } },
        as: :turbo_stream
    end
    assert_response :success
  end

  test "create without content returns bad request" do
    post meeting_chat_messages_url(@meeting, @chat),
      params: { message: { content: "" } }
    assert_response :bad_request
  end

  test "create requires authentication" do
    sign_out
    post meeting_chat_messages_url(@meeting, @chat),
      params: { message: { content: "Hello" } }
    assert_redirected_to new_session_url
  end

  test "create scopes to current user's meeting" do
    sign_in_as(users(:two))
    post meeting_chat_messages_url(@meeting, @chat),
      params: { message: { content: "Hello" } }
    assert_response :not_found
  end
end
