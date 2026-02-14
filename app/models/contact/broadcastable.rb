module Contact::Broadcastable
  extend ActiveSupport::Concern

  included do
    after_create_commit :broadcast_contact_created
    after_update_commit :broadcast_contact_updated
    after_destroy_commit :broadcast_contact_destroyed
    after_update_commit :broadcast_meeting_participants, if: :saved_change_to_name_or_email?
  end

  private

  def broadcast_contact_created
    broadcast_append_to user,
      target: "contacts_list",
      partial: "contacts/contact",
      locals: { contact: self }
  end

  def broadcast_contact_updated
    broadcast_replace_to user,
      target: dom_id,
      partial: "contacts/contact",
      locals: { contact: self }
  end

  def broadcast_contact_destroyed
    broadcast_remove_to user,
      target: dom_id
  end

  def broadcast_meeting_participants
    meeting_participants.includes(:meeting).each do |participant|
      broadcast_replace_to participant.meeting,
        target: "meeting_participants",
        partial: "meetings/participants",
        locals: { meeting: participant.meeting }
    end
  end

  def saved_change_to_name_or_email?
    saved_change_to_name? || saved_change_to_email?
  end

  def dom_id
    ActionView::RecordIdentifier.dom_id(self)
  end
end
