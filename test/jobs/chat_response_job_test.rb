require "test_helper"

class ChatResponseJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

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
end
