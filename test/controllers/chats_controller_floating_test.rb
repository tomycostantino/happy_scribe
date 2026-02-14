require "test_helper"

class Chats::FloatingControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as(users(:one))
  end

  test "show returns existing standalone chat" do
    get chats_floating_url

    assert_response :success
    assert_match "floating_chat", response.body
  end

  test "show creates new chat when none exists" do
    users(:one).chats.where(meeting_id: nil).destroy_all

    assert_difference "Chat.count", 1 do
      get chats_floating_url
    end

    assert_response :success
  end

  test "show ignores meeting-scoped chats" do
    users(:one).chats.where(meeting_id: nil).destroy_all

    assert_difference "Chat.count", 1 do
      get chats_floating_url
    end

    assert_response :success
    assert_nil Chat.last.meeting_id
  end

  test "show returns most recent standalone chat" do
    older_chat = chats(:standalone)
    newer_chat = users(:one).chats.create!

    get chats_floating_url

    assert_response :success
    assert_match "/chats/#{newer_chat.id}/messages", response.body
  end

  test "create creates a new chat" do
    assert_difference "Chat.count", 1 do
      post chats_floating_url
    end

    assert_response :success
    assert_nil Chat.last.meeting_id
  end

  test "create returns turbo frame content" do
    post chats_floating_url

    assert_response :success
    assert_match "floating_chat", response.body
  end

  test "show requires authentication" do
    sign_out
    get chats_floating_url

    assert_redirected_to new_session_url
  end

  test "create requires authentication" do
    sign_out
    post chats_floating_url

    assert_redirected_to new_session_url
  end
end
