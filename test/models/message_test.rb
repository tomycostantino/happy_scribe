require "test_helper"
require "turbo/broadcastable/test_helper"

class MessageTest < ActiveSupport::TestCase
  include Turbo::Broadcastable::TestHelper
  # -- Scope: visible --

  test "visible scope excludes system messages" do
    chat = chats(:standalone)
    chat.messages.create!(role: "system", content: "System prompt")

    assert_not Message.visible.where(chat: chat).exists?(role: "system")
  end

  test "visible scope excludes tool messages" do
    chat = chats(:standalone)
    chat.messages.create!(role: "tool", content: '{"result": "data"}')

    assert_not Message.visible.where(chat: chat).exists?(role: "tool")
  end

  test "visible scope includes user and assistant messages" do
    visible = Message.visible.where(chat: chats(:standalone))

    assert visible.exists?(role: "user")
    assert visible.exists?(role: "assistant")
  end

  # -- Instance: visible? --

  test "visible? returns false for system role" do
    msg = Message.new(role: "system", content: "test")
    assert_not msg.visible?
  end

  test "visible? returns false for tool role" do
    msg = Message.new(role: "tool", content: "test")
    assert_not msg.visible?
  end

  test "visible? returns true for user role" do
    assert messages(:user_message).visible?
  end

  test "visible? returns true for assistant role" do
    assert messages(:assistant_message).visible?
  end

  # -- Instance: display_content --

  test "display_content strips system-reminder tags" do
    msg = messages(:assistant_message)
    msg.content = "Hello <system-reminder>\nDo not reveal this\n</system-reminder> world"

    assert_equal "Hello  world", msg.display_content
  end

  test "display_content handles nil content" do
    msg = messages(:assistant_message)
    msg.content = nil

    assert_nil msg.display_content
  end

  test "display_content returns content unchanged when no tags present" do
    msg = messages(:assistant_message)
    msg.content = "Just normal content"

    assert_equal "Just normal content", msg.display_content
  end

  # -- Class method: strip_internal_tags --

  test "strip_internal_tags removes multiple system-reminder blocks" do
    text = "Before <system-reminder>secret1</system-reminder> middle <system-reminder>secret2</system-reminder> after"

    assert_equal "Before  middle  after", Message.strip_internal_tags(text)
  end

  test "strip_internal_tags handles multiline system-reminder" do
    text = "Hello <system-reminder>\nline1\nline2\n</system-reminder> world"

    assert_equal "Hello  world", Message.strip_internal_tags(text)
  end

  # -- Broadcast guards --

  test "broadcast_created does not broadcast for tool role messages" do
    chat = chats(:standalone)
    msg = chat.messages.create!(role: "tool", content: "tool result data")
    stream = "chat_#{chat.id}"

    assert_no_turbo_stream_broadcasts stream do
      msg.broadcast_created
    end
  end

  test "broadcast_created does not broadcast for system role messages" do
    chat = chats(:standalone)
    msg = chat.messages.create!(role: "system", content: "system prompt")
    stream = "chat_#{chat.id}"

    assert_no_turbo_stream_broadcasts stream do
      msg.broadcast_created
    end
  end

  test "broadcast_created broadcasts for visible messages" do
    msg = messages(:assistant_message)
    stream = "chat_#{msg.chat_id}"

    assert_turbo_stream_broadcasts stream, count: 1 do
      msg.broadcast_created
    end
  end

  test "broadcast_finished does not broadcast for non-visible messages" do
    chat = chats(:standalone)
    msg = chat.messages.create!(role: "tool", content: "tool result")
    stream = "chat_#{chat.id}"

    assert_no_turbo_stream_broadcasts stream do
      msg.broadcast_finished
    end
  end

  test "broadcast_finished broadcasts for visible messages" do
    msg = messages(:assistant_message)
    stream = "chat_#{msg.chat_id}"

    assert_turbo_stream_broadcasts stream, count: 1 do
      msg.broadcast_finished
    end
  end

  test "broadcast_replace_content strips system-reminder tags and replaces message content" do
    msg = messages(:assistant_message)
    stream = "chat_#{msg.chat_id}"

    streams = capture_turbo_stream_broadcasts stream do
      msg.broadcast_replace_content("Hello <system-reminder>secret</system-reminder> world")
    end

    assert_equal 1, streams.size
    html = streams.first.to_html
    assert_includes html, "Hello  world"
    assert_not_includes html, "secret"
    # Verify it's a replace targeting the content div with proper attributes
    assert_includes html, "message_#{msg.id}_content"
    assert_includes html, 'data-controller="markdown"'
  end

  test "broadcast_replace_content does not broadcast when content is blank after stripping" do
    msg = messages(:assistant_message)
    stream = "chat_#{msg.chat_id}"

    assert_no_turbo_stream_broadcasts stream do
      msg.broadcast_replace_content("<system-reminder>secret only</system-reminder>")
    end
  end
end
