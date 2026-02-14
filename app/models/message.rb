class Message < ApplicationRecord
  acts_as_message
  has_many_attached :attachments

  def broadcast_created
    broadcast_append_to "chat_#{chat_id}",
      target: "messages"
  end

  def broadcast_append_chunk(content)
    broadcast_append_to "chat_#{chat_id}",
      target: "message_#{id}_content",
      html: content
  end

  def broadcast_finished
    broadcast_replace_to "chat_#{chat_id}"
  end
end
