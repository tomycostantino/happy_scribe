require "test_helper"

class ChatTest < ActiveSupport::TestCase
  test "belongs to user" do
    chat = chats(:standalone)
    assert_equal users(:one), chat.user
  end

  test "meeting is optional" do
    chat = chats(:standalone)
    assert_nil chat.meeting
    assert chat.valid?
  end

  test "can belong to meeting" do
    chat = chats(:meeting_chat)
    assert_equal meetings(:one), chat.meeting
  end

  test "has many messages" do
    chat = chats(:standalone)
    assert_includes chat.messages, messages(:user_message)
    assert_includes chat.messages, messages(:assistant_message)
  end

  test "with_meeting_assistant returns self when no meeting" do
    chat = chats(:standalone)
    assert_equal chat, chat.with_meeting_assistant
  end

  test "with_meeting_assistant returns self when transcript not completed" do
    chat = chats(:meeting_chat)
    chat.meeting.transcript.update!(status: :processing)
    assert_equal chat, chat.with_meeting_assistant
  end

  test "with_meeting_assistant sets system prompt when transcript completed" do
    chat = chats(:meeting_chat)
    assert chat.meeting.transcript.completed?

    chat.with_meeting_assistant

    system_message = chat.messages.find_by(role: "system")
    assert_not_nil system_message
    assert_includes system_message.content, "Weekly Standup"
    assert_includes system_message.content, "Hello everyone, welcome to the weekly standup."
  end

  test "with_meeting_assistant includes formatted transcript text" do
    chat = chats(:meeting_chat)
    chat.with_meeting_assistant

    system_message = chat.messages.find_by(role: "system")
    assert_includes system_message.content, "Speaker 1 [00:00:00]:"
    assert_includes system_message.content, "Speaker 2 [00:00:03]:"
  end

  test "with_meeting_assistant replaces existing system prompt" do
    chat = chats(:meeting_chat)

    # Call twice — should not create duplicate system messages
    chat.with_meeting_assistant
    chat.with_meeting_assistant

    system_messages = chat.messages.where(role: "system")
    assert_equal 1, system_messages.count
  end
end
