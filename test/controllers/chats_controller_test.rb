require "test_helper"

class ChatsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
  end

  test "index shows user's chats" do
    get chats_url
    assert_response :success
  end

  test "index requires authentication" do
    sign_out
    get chats_url
    assert_redirected_to new_session_url
  end

  test "new shows form" do
    get new_chat_url
    assert_response :success
  end

  test "show displays chat" do
    get chat_url(chats(:standalone))
    assert_response :success
  end

  test "show scopes to current user" do
    sign_in_as(users(:two))
    get chat_url(chats(:standalone))
    assert_response :not_found
  end

  test "create with prompt enqueues ChatResponseJob" do
    assert_enqueued_with(job: ChatResponseJob) do
      post chats_url, params: { chat: { prompt: "Hello", model: "" } }
    end
    assert_redirected_to chat_url(Chat.last)
  end

  test "create without prompt returns bad request" do
    post chats_url, params: { chat: { prompt: "", model: "" } }
    assert_response :bad_request
  end
end
