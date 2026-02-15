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

    @assistant_message = nil
    @accumulated_content = ""
    @last_broadcast_at = 0
    @thinking_removed = false

    chat.complete do |chunk|
      next if chunk.content.blank?

      current_message = chat.messages.where(role: "assistant").order(:created_at).last

      # Detect when a new assistant message has started (multi-round tool calls
      # cause RubyLLM to create multiple assistant messages via recursive complete).
      if @assistant_message.nil? || current_message.id != @assistant_message.id
        # Finalize the previous message if we were streaming one
        finalize_streamed_message if @assistant_message

        # Start streaming the new message
        @assistant_message = current_message
        @accumulated_content = ""
        start_streaming(chat, @assistant_message)
      end

      @accumulated_content += chunk.content
      broadcast_content_debounced
    end

    # Finalize the last streamed message
    if @assistant_message
      finalize_streamed_message
    else
      # No content was streamed at all (pure tool-call-only response)
      finish_without_streaming(chat)
    end
  rescue => e
    Rails.logger.error("ChatResponseJob failed for chat #{chat_id}: #{e.message}")
    handle_failure(chat, e)
    raise if e.is_a?(RubyLLM::Error)
  end

  private

  # Introduces a new assistant message into the DOM and removes the thinking
  # indicator on the first message.
  def start_streaming(chat, assistant_message)
    unless @thinking_removed
      remove_thinking(chat)
      @thinking_removed = true
    end

    assistant_message.broadcast_created
  end

  # Broadcasts the final accumulated content, then replaces the streamed element
  # with the fully rendered partial from the database.
  def finalize_streamed_message
    broadcast_content_now
    @assistant_message.reload
    @assistant_message.broadcast_finished
  end

  # Handles the case where no text chunks were streamed at all (e.g. a
  # tool-call-only response with no user-visible text).
  def finish_without_streaming(chat)
    last_msg = chat.messages.where(role: "assistant").order(:created_at).last

    remove_thinking(chat) unless @thinking_removed
    last_msg&.broadcast_created
    last_msg&.reload
    last_msg&.broadcast_finished
  end

  def handle_failure(chat, error)
    @assistant_message ||= chat.messages.where(role: "assistant")
                                .where(content: [ "", nil ])
                                .order(:created_at).last

    remove_thinking(chat) unless @thinking_removed

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
