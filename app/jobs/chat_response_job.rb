class ChatResponseJob < ApplicationJob
  def perform(chat_id, content)
    chat = Chat.find(chat_id)

    # Inject meeting transcript as system prompt when chat belongs to a meeting
    chat.with_meeting_assistant if chat.meeting

    chat.ask(content) do |chunk|
      if chunk.content && !chunk.content.blank?
        message = chat.messages.last
        message.broadcast_append_chunk(chunk.content)
      end
    end
  end
end
