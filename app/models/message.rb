class Message < ApplicationRecord
  acts_as_message
  has_many_attached :attachments

  INTERNAL_ROLES = %w[system tool].freeze
  SYSTEM_REMINDER_PATTERN = /<system-reminder>.*?<\/system-reminder>/m

  # The .where.not(id: nil) clause filters out unsaved in-memory records that
  # RubyLLM's acts_as_message may include in the association.
  scope :visible, -> { where.not(role: INTERNAL_ROLES).where.not(id: nil) }

  def visible?
    !role.in?(INTERNAL_ROLES)
  end

  # Returns content safe for display, stripping any internal tags
  # injected by the LLM provider (e.g. <system-reminder>).
  def display_content
    self.class.strip_internal_tags(content)
  end

  def self.strip_internal_tags(text)
    return text if text.blank?
    text.gsub(SYSTEM_REMINDER_PATTERN, "")
  end

  # Broadcasts this message appended to the chat's message list.
  # Used for messages created in background jobs (e.g. assistant messages).
  def broadcast_created
    return unless visible?

    broadcast_append_to "chat_#{chat_id}",
      target: "chat_#{chat_id}_messages"
  end

  # Replaces the message content div with accumulated raw text during streaming.
  # Uses Turbo Stream "replace" instead of "append" so only one element exists
  # at a time, preventing text chunks from piling up in the DOM.
  def broadcast_replace_content(content)
    cleaned = self.class.strip_internal_tags(content)
    return if cleaned.blank?

    broadcast_replace_to "chat_#{chat_id}",
      target: "message_#{id}_content",
      html: content_div(cleaned)
  end

  # Replaces the message element with the final rendered version.
  def broadcast_finished
    return unless visible?

    broadcast_replace_to "chat_#{chat_id}"
  end

  private

  # Builds the content div HTML for streaming replacements.
  # Must include the same id, classes, and data-controller attributes
  # so that Turbo can find the target on subsequent replaces and
  # Stimulus reconnects the markdown controller.
  def content_div(text)
    %(<div id="message_#{id}_content" class="text-sm text-gray-700 prose prose-sm max-w-none" data-controller="markdown">#{text}</div>)
  end
end
