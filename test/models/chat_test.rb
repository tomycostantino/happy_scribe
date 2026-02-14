require "test_helper"

class ChatTest < ActiveSupport::TestCase
  setup do
    # Ensure chunks exist for RAG tests
    transcripts(:one).transcript_chunks.delete_all
    Transcript::Embedder.perform_now(meetings(:one).id)
  end

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

  test "with_meeting_assistant returns self when no chunks exist" do
    chat = chats(:meeting_chat)
    chat.meeting.transcript.transcript_chunks.delete_all

    assert_equal chat, chat.with_meeting_assistant
    assert_nil chat.messages.find_by(role: "system")
  end

  test "with_meeting_assistant sets system prompt with relevant chunks" do
    chat = chats(:meeting_chat)
    chat.with_meeting_assistant(user_message: "API integration")

    system_message = chat.messages.find_by(role: "system")
    assert_not_nil system_message
    assert_includes system_message.content, "Weekly Standup"
    assert_includes system_message.content, "selected portions"
  end

  test "with_meeting_assistant includes transcript content in chunks" do
    chat = chats(:meeting_chat)
    chat.with_meeting_assistant(user_message: "standup")

    system_message = chat.messages.find_by(role: "system")
    assert_includes system_message.content, "Speaker 1"
  end

  test "with_meeting_assistant replaces system prompt on each call" do
    chat = chats(:meeting_chat)

    chat.with_meeting_assistant(user_message: "first question")
    chat.with_meeting_assistant(user_message: "second question")

    system_messages = chat.messages.where(role: "system")
    assert_equal 1, system_messages.count
  end

  test "with_meeting_assistant falls back to positional chunks when no text match" do
    chat = chats(:meeting_chat)
    chat.with_meeting_assistant(user_message: "xyzzy nonexistent gibberish")

    system_message = chat.messages.find_by(role: "system")
    assert_not_nil system_message
    assert_includes system_message.content, "selected portions"
  end

  test "with_meeting_assistant works with blank user message" do
    chat = chats(:meeting_chat)
    chat.with_meeting_assistant

    system_message = chat.messages.find_by(role: "system")
    assert_not_nil system_message
    assert_includes system_message.content, "selected portions"
  end

  # --- Agentic assistant (standalone chats with tools) ---

  test "with_assistant sets cross-meeting system prompt" do
    chat = chats(:standalone)
    chat.with_assistant

    system_message = chat.messages.find_by(role: "system")
    assert_not_nil system_message
    assert_includes system_message.content, "meeting assistant"
    assert_includes system_message.content, Date.today.to_s
  end

  test "with_assistant registers RubyLLM tools" do
    chat = chats(:standalone)
    result = chat.with_assistant

    # with_assistant returns self for chaining
    assert_equal chat, result

    # The underlying RubyLLM::Chat should have tools registered
    llm_chat = chat.to_llm
    assert llm_chat.tools.any?, "Expected tools to be registered"
  end

  test "with_assistant replaces system prompt on each call" do
    chat = chats(:standalone)

    chat.with_assistant
    chat.with_assistant

    system_messages = chat.messages.where(role: "system")
    assert_equal 1, system_messages.count
  end

  test "with_assistant returns self for chaining" do
    chat = chats(:standalone)
    assert_equal chat, chat.with_assistant
  end

  # --- Meeting assistant also has tools ---

  test "with_meeting_assistant registers tools on the chat" do
    chat = chats(:meeting_chat)
    chat.with_meeting_assistant(user_message: "action items")

    llm_chat = chat.to_llm
    assert llm_chat.tools.any?, "Expected tools to be registered on meeting chat"
  end

  test "with_meeting_assistant system prompt mentions tool capabilities" do
    chat = chats(:meeting_chat)
    chat.with_meeting_assistant(user_message: "what happened")

    system_message = chat.messages.find_by(role: "system")
    assert_includes system_message.content, "action item"
  end

  # --- Tool-driven quick-action buttons ---

  test "meeting_tool_buttons returns array of label/prompt pairs" do
    buttons = Chat.meeting_tool_buttons
    assert buttons.is_a?(Array)
    assert buttons.length >= 2
    buttons.each do |label, prompt|
      assert label.present?, "Button label should be present"
      assert prompt.present?, "Button prompt should be present"
    end
  end

  test "meeting_tool_buttons includes buttons from tools that define them" do
    buttons = Chat.meeting_tool_buttons
    labels = buttons.map(&:first)
    assert_includes labels, "Summarize meeting"
    assert_includes labels, "List action items"
    assert_includes labels, "Extract & save action items"
  end

  test "meeting_tool_buttons does not include tools without button metadata" do
    buttons = Chat.meeting_tool_buttons
    labels = buttons.map(&:first)
    # MeetingLookupTool should not appear as a meeting quick-action button
    refute labels.any? { |l| l.downcase.include?("lookup") }
  end
end
