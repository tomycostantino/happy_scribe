class ChatResponseJob < ApplicationJob
  queue_as :llm

  retry_on RubyLLM::Error, wait: :polynomially_longer, attempts: 3

  def perform(chat_id)
    chat = Chat.find(chat_id)
    user_content = last_user_content(chat)

    if chat.meeting
      chat.with_meeting_assistant(user_message: user_content)
    else
      chat.with_assistant
    end

    streaming_started = false
    @accumulated_content = ""
    @last_broadcast_at = 0

    chat.complete do |chunk|
      next if chunk.content.blank?

      unless streaming_started
        streaming_started = true
        @assistant_message = chat.messages.where(role: "assistant").order(:created_at).last
        broadcast_start(chat, @assistant_message)
      end

      @accumulated_content += chunk.content
      broadcast_content_debounced
    end

    # Ensure the final accumulated content is broadcast before finishing
    broadcast_content_now if streaming_started
    finish_streaming(chat, streaming_started)
  rescue => e
    Rails.logger.error("ChatResponseJob failed for chat #{chat_id}: #{e.message}")
    handle_failure(chat, e)
    raise if e.is_a?(RubyLLM::Error)
  end

  private

  def broadcast_start(chat, assistant_message)
    remove_thinking(chat)
    assistant_message.broadcast_created
  end

  def finish_streaming(chat, streaming_started)
    @assistant_message ||= chat.messages.where(role: "assistant").order(:created_at).last

    # If no content chunks arrived during streaming (e.g. tool-call-only
    # responses), the thinking indicator is still in the DOM. Remove it
    # and broadcast the assistant message into the page for the first time.
    unless streaming_started
      remove_thinking(chat)
      @assistant_message&.broadcast_created
    end

    @assistant_message&.reload
    @assistant_message&.broadcast_finished
  end

  def handle_failure(chat, error)
    @assistant_message ||= chat.messages.where(role: "assistant")
                               .where(content: [ "", nil ])
                               .order(:created_at).last

    remove_thinking(chat)

    if @assistant_message
      @assistant_message.update(content: "Sorry, something went wrong generating a response. Please try again.")
      @assistant_message.broadcast_created
      @assistant_message.broadcast_finished
    else
      Turbo::StreamsChannel.broadcast_append_to "chat_#{chat.id}",
        target: "chat_#{chat.id}_messages",
        html: '<div class="rounded-md px-3 py-2 bg-red-50 mr-8 text-sm text-red-700">Sorry, something went wrong. Please try again.</div>'
    end
  rescue => broadcast_error
    Rails.logger.error("ChatResponseJob failed to broadcast error for chat #{chat.id}: #{broadcast_error.message}")
  end

  # Minimum interval between streaming broadcasts (in milliseconds).
  # Prevents flooding ActionCable while keeping responses feeling responsive.
  BROADCAST_INTERVAL_MS = 50

  def broadcast_content_debounced
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
    return if (now - @last_broadcast_at) < BROADCAST_INTERVAL_MS

    broadcast_content_now
  end

  def broadcast_content_now
    return unless @assistant_message && @accumulated_content.present?

    @assistant_message.broadcast_replace_content(@accumulated_content)
    @last_broadcast_at = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
  end

  def remove_thinking(chat)
    Turbo::StreamsChannel.broadcast_remove_to "chat_#{chat.id}",
      target: "chat_#{chat.id}_thinking"
  end

  def last_user_content(chat)
    chat.messages.where(role: "user").order(:created_at).last&.content
  end
end
