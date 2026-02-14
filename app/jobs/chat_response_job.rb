class ChatResponseJob < ApplicationJob
  def perform(chat_id, content)
    chat = Chat.find(chat_id)

    # Inject meeting transcript as system prompt when chat belongs to a meeting
    chat.with_meeting_assistant if chat.meeting

    streaming_started = false

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

        chat.messages.where(role: "assistant").order(:created_at).last
          .broadcast_append_chunk(chunk.content)
      end
    end

    # Replace assistant message with final content (includes token counts, etc.)
    chat.messages.where(role: "assistant").order(:created_at).last
      &.broadcast_finished
  end
end
