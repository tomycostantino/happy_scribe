require "test_helper"

class MessagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
    @chat = chats(:standalone)
  end

  test "create enqueues ChatResponseJob" do
    assert_enqueued_with(job: ChatResponseJob) do
      post chat_messages_url(@chat), params: { message: { content: "Hello" } }
    end
  end

  test "create with turbo stream format" do
    assert_enqueued_with(job: ChatResponseJob) do
      post chat_messages_url(@chat),
        params: { message: { content: "Hello" } },
        as: :turbo_stream
    end
    assert_response :success
  end

  test "create without content returns bad request" do
    post chat_messages_url(@chat), params: { message: { content: "" } }
    assert_response :bad_request
  end

  test "create requires authentication" do
    sign_out
    post chat_messages_url(@chat), params: { message: { content: "Hello" } }
    assert_redirected_to new_session_url
  end

  test "create scopes chat to current user" do
    sign_in_as(users(:two))
    post chat_messages_url(@chat), params: { message: { content: "Hello" } }
    assert_response :not_found
  end
end
