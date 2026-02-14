require "test_helper"

class Chats::FloatingControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
  end

  test "index lists standalone chats" do
    get chats_floating_index_url

    assert_response :success
    assert_match "floating_chat", response.body
  end

  test "index does not list meeting-scoped chats" do
    get chats_floating_index_url

    assert_response :success
    # Meeting-scoped chat should not appear
    meeting_chat = chats(:meeting_chat)
    assert_no_match meeting_chat.id.to_s, response.body
  end

  test "show returns a specific chat" do
    chat = chats(:standalone)

    get chats_floating_url(chat)

    assert_response :success
    assert_match "floating_chat", response.body
    assert_match "/chats/#{chat.id}/messages", response.body
  end

  test "show returns most recent standalone chat when given its id" do
    older_chat = chats(:standalone)
    newer_chat = users(:one).chats.create!

    get chats_floating_url(newer_chat)

    assert_response :success
    assert_match "/chats/#{newer_chat.id}/messages", response.body
  end

  test "create creates a new chat" do
    assert_difference "Chat.count", 1 do
      post chats_floating_index_url
    end

    assert_response :success
    assert_nil Chat.last.meeting_id
  end

  test "create returns turbo frame content" do
    post chats_floating_index_url

    assert_response :success
    assert_match "floating_chat", response.body
  end

  test "destroy deletes a chat and renders index" do
    chat = chats(:standalone)

    assert_difference "Chat.count", -1 do
      delete chats_floating_url(chat)
    end

    assert_response :success
    assert_match "floating_chat", response.body
  end

  test "index requires authentication" do
    sign_out
    get chats_floating_index_url

    assert_redirected_to new_session_url
  end

  test "show requires authentication" do
    sign_out
    get chats_floating_url(chats(:standalone))

    assert_redirected_to new_session_url
  end

  test "create requires authentication" do
    sign_out
    post chats_floating_index_url

    assert_redirected_to new_session_url
  end

  test "destroy requires authentication" do
    sign_out
    delete chats_floating_url(chats(:standalone))

    assert_redirected_to new_session_url
  end
end
