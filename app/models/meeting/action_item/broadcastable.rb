module Meeting::ActionItem::Broadcastable
  extend ActiveSupport::Concern

  included do
    after_update_commit :broadcast_action_items, if: :saved_change_to_completed?
  end

  private

  def broadcast_action_items
    broadcast_replace_to meeting,
      target: "meeting_#{meeting_id}_action_items",
      partial: "meetings/action_items",
      locals: { meeting: meeting }
  end
end
