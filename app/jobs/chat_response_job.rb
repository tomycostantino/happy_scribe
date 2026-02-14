class ChatResponseJob < ApplicationJob
  queue_as :llm

  retry_on RubyLLM::Error, wait: :polynomially_longer, attempts: 3

  def perform(chat_id, content)
    chat = Chat.find(chat_id)

    if chat.meeting
      # Inject meeting transcript as system prompt for meeting-scoped chats
      chat.with_meeting_assistant(user_message: content)
    else
      # Register agentic tools for standalone cross-meeting chats
      chat.with_assistant
    end

    streaming_started = false
    assistant_message = nil

    chat.ask(content) do |chunk|
      if chunk.content.present?
        unless streaming_started
          streaming_started = true
          # Broadcast both messages before any chunks so DOM targets exist
          user_message = chat.messages.where(role: "user").order(:created_at).last
          assistant_message = chat.messages.where(role: "assistant").order(:created_at).last
          user_message.broadcast_created
          assistant_message.broadcast_created
        end

        assistant_message.broadcast_append_chunk(chunk.content)
      end
    end

    # Reload to pick up content written by RubyLLM's persist_message_completion
    assistant_message ||= chat.messages.where(role: "assistant").order(:created_at).last
    assistant_message&.reload
    assistant_message&.broadcast_finished
  rescue => e
    Rails.logger.error("ChatResponseJob failed for chat #{chat_id}: #{e.message}")
    # Find the empty assistant message even if streaming hadn't started yet.
    # RubyLLM's persist_new_message creates a Message(content: '') before the
    # API responds — if the call fails before any chunk arrives, that empty
    # message stays in the DB and poisons all future requests ("content missing").
    assistant_message ||= chat.messages.where(role: "assistant").where(content: [ "", nil ]).order(:created_at).last
    broadcast_error(chat, assistant_message, e)
    raise if e.is_a?(RubyLLM::Error) # let retry_on handle retryable errors
  end

  private

  def broadcast_error(chat, assistant_message, error)
    if assistant_message
      assistant_message.update(content: "Sorry, something went wrong generating a response. Please try again.")
      assistant_message.broadcast_finished
    end
  rescue => broadcast_error
    Rails.logger.error("ChatResponseJob failed to broadcast error for chat #{chat.id}: #{broadcast_error.message}")
  end
end
