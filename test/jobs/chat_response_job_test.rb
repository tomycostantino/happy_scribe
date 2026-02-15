require "test_helper"
require "turbo/broadcastable/test_helper"

class ChatResponseJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include Turbo::Broadcastable::TestHelper

  test "job is enqueued on llm queue" do
    assert_equal "llm", ChatResponseJob.new.queue_name
  end

  test "retries on RubyLLM::Error" do
    handlers = ChatResponseJob.rescue_handlers
    assert handlers.any? { |h| h.first == "RubyLLM::Error" }
  end

  test "calls with_assistant for standalone chats" do
    chat = chats(:standalone)
    assistant_called = false

    chat.stub(:with_assistant, -> { assistant_called = true; chat }) do
      chat.stub(:complete, ->(&_block) { }) do
        Chat.stub(:find, chat) do
          ChatResponseJob.perform_now(chat.id)
        end
      end
    end

    assert assistant_called, "Expected with_assistant to be called for standalone chat"
  end

  test "calls with_meeting_assistant for meeting chats" do
    chat = chats(:meeting_chat)
    meeting_assistant_called = false

    chat.stub(:with_meeting_assistant, ->(**_kwargs) { meeting_assistant_called = true; chat }) do
      chat.stub(:complete, ->(&_block) { }) do
        Chat.stub(:find, chat) do
          ChatResponseJob.perform_now(chat.id)
        end
      end
    end

    assert meeting_assistant_called, "Expected with_meeting_assistant to be called for meeting chat"
  end

  # Simulates the RubyLLM streaming lifecycle for multi-round tool calls.
  # RubyLLM fires on_new_message before each message (assistant and tool),
  # fires the streaming block with chunks, then fires on_end_message.
  # Tool calls cause recursive complete() calls with the same streaming block.

  test "multi-round tool calls: each assistant message gets broadcast_created and broadcast_finished" do
    chat = chats(:standalone)
    # Clear fixture messages so we start fresh for this simulation
    chat.messages.destroy_all
    chat.messages.create!(role: "user", content: "Look up some data for me")
    stream = "chat_#{chat.id}"

    # Track all broadcasts
    broadcasts = capture_turbo_stream_broadcasts(stream) do
      chat.stub(:with_assistant, chat) do
        chat.stub(:complete, ->(& block) { simulate_multi_round_tool_call(chat, block) }) do
          Chat.stub(:find, chat) do
            ChatResponseJob.perform_now(chat.id)
          end
        end
      end
    end

    # Should have broadcast_created (append) + streaming replaces + broadcast_finished (replace)
    # for EACH visible assistant message, not just the first one.
    assistant_messages = chat.messages.where(role: "assistant").where.not(content: [ "", nil ]).order(:created_at)
    assert_equal 2, assistant_messages.count, "Expected 2 assistant messages with content"

    # Find append broadcasts (broadcast_created) — one per visible assistant message
    appends = broadcasts.select { |b| b["action"] == "append" }
    assert_equal 2, appends.count,
      "Expected 2 append broadcasts (broadcast_created for each assistant message), got #{appends.count}"

    # Each assistant message should have a corresponding replace broadcast (broadcast_finished)
    assistant_messages.each do |msg|
      replaces = broadcasts.select { |b| b["action"] == "replace" && b["target"] == "message_#{msg.id}" }
      assert replaces.any?,
        "Expected broadcast_finished (replace) for message #{msg.id} with content: #{msg.content.truncate(40)}"
    end
  end

  test "multi-round tool calls: final broadcast_finished renders correct content for each message" do
    chat = chats(:standalone)
    chat.messages.destroy_all
    chat.messages.create!(role: "user", content: "Look up some data for me")
    stream = "chat_#{chat.id}"

    broadcasts = capture_turbo_stream_broadcasts(stream) do
      chat.stub(:with_assistant, chat) do
        chat.stub(:complete, ->(& block) { simulate_multi_round_tool_call(chat, block) }) do
          Chat.stub(:find, chat) do
            ChatResponseJob.perform_now(chat.id)
          end
        end
      end
    end

    assistant_messages = chat.messages.where(role: "assistant").where.not(content: [ "", nil ]).order(:created_at)
    first_msg, second_msg = assistant_messages.to_a

    # The final replace for each message should contain that message's content
    first_replace = broadcasts.select { |b| b["action"] == "replace" && b["target"] == "message_#{first_msg.id}" }.last
    second_replace = broadcasts.select { |b| b["action"] == "replace" && b["target"] == "message_#{second_msg.id}" }.last

    assert first_replace, "Expected a replace broadcast for first assistant message"
    assert second_replace, "Expected a replace broadcast for second assistant message"

    first_html = first_replace.to_html
    second_html = second_replace.to_html

    assert_includes first_html, "Let me look that up",
      "First message broadcast_finished should contain first message content"
    assert_includes second_html, "Here are the results",
      "Second message broadcast_finished should contain second message content"
  end

  test "single response without tool calls still works correctly" do
    chat = chats(:standalone)
    chat.messages.destroy_all
    chat.messages.create!(role: "user", content: "Hello")
    stream = "chat_#{chat.id}"

    broadcasts = capture_turbo_stream_broadcasts(stream) do
      chat.stub(:with_assistant, chat) do
        chat.stub(:complete, ->(& block) { simulate_simple_response(chat, block) }) do
          Chat.stub(:find, chat) do
            ChatResponseJob.perform_now(chat.id)
          end
        end
      end
    end

    assistant_messages = chat.messages.where(role: "assistant").where.not(content: [ "", nil ]).order(:created_at)
    assert_equal 1, assistant_messages.count

    appends = broadcasts.select { |b| b["action"] == "append" }
    assert_equal 1, appends.count, "Expected 1 append broadcast for single response"

    msg = assistant_messages.first
    replaces = broadcasts.select { |b| b["action"] == "replace" && b["target"] == "message_#{msg.id}" }
    assert replaces.any?, "Expected broadcast_finished for the single assistant message"
  end

  private

  # Simulates RubyLLM's behavior during a multi-round tool call:
  # Round 1: AI says "Let me look that up..." then calls a tool
  # Round 2: AI says "Here are the results..." (final answer)
  #
  # RubyLLM's lifecycle per round:
  # 1. on_new_message callback fires (creates assistant message in DB)
  # 2. Streaming block receives chunks
  # 3. on_end_message callback fires (persists content to DB)
  # For tool calls: on_new_message for tool result, on_end_message for tool result
  # Then recursive complete() for next round.
  def simulate_multi_round_tool_call(chat, block)
    chunk = Struct.new(:content)

    # --- Round 1: Assistant message with text + tool call ---
    # on_new_message fires → persistence creates assistant message
    fire_on_new_message(chat)
    msg1 = chat.messages.where(role: "assistant").order(:created_at).last

    # Stream some text chunks
    block.call(chunk.new("Let me "))
    block.call(chunk.new("look that up"))
    block.call(chunk.new("..."))

    # on_end_message fires → persistence saves content
    msg1.update!(content: "Let me look that up...")

    # Tool call happens: on_new_message for tool result
    fire_on_new_message(chat)
    tool_msg = chat.messages.where(role: "assistant").order(:created_at).last
    tool_msg.update!(role: "tool", content: '{"result": "some data"}')

    # --- Round 2: Recursive complete() - Final answer ---
    # on_new_message fires → persistence creates new assistant message
    fire_on_new_message(chat)
    msg2 = chat.messages.where(role: "assistant").order(:created_at).last

    # Stream the final answer
    block.call(chunk.new("Here are "))
    block.call(chunk.new("the results"))
    block.call(chunk.new(" from the tool."))

    # on_end_message fires → persistence saves content
    msg2.update!(content: "Here are the results from the tool.")
  end

  # Simulates a simple response without tool calls
  def simulate_simple_response(chat, block)
    chunk = Struct.new(:content)

    fire_on_new_message(chat)
    msg = chat.messages.where(role: "assistant").order(:created_at).last

    block.call(chunk.new("Hello, "))
    block.call(chunk.new("how can I help?"))

    msg.update!(content: "Hello, how can I help?")
  end

  # Fires the on_new_message callback chain on the chat's underlying RubyLLM chat,
  # which triggers persist_new_message (creating a new assistant message in DB).
  def fire_on_new_message(chat)
    chat.messages.create!(role: "assistant", content: "")
  end
end
