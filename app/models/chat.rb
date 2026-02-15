class Chat < ApplicationRecord
  acts_as_chat
  include Toolable
  include Promptable
  include Respondable

  belongs_to :user
  belongs_to :meeting, optional: true

  # Returns a short preview string for display in chat lists.
  # Uses the first user message content, truncated to 60 characters.
  def preview
    first_message = messages.where(role: "user").order(:created_at).first
    return "New chat" unless first_message&.content.present?

    first_message.content.truncate(60)
  end
end
