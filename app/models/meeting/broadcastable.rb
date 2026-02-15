# Broadcasts real-time Turbo Stream updates when meeting status changes.
#
# Sends updates to two streams:
# - The meeting stream (for the show page): replaces the entire content area
# - The user stream (for the index page): replaces the meeting row
#
# Provides `transition_status!` for status changes that bypass validations
# (useful in background jobs where the meeting may lack attached files).
module Meeting::Broadcastable
  extend ActiveSupport::Concern

  included do
    after_create_commit :broadcast_created
    after_update_commit :broadcast_status_change, if: :saved_change_to_status?
  end

  # Update status without running validations and broadcast the change.
  # Use this instead of update_column(:status, ...) to ensure broadcasts fire.
  def transition_status!(new_status)
    update_column(:status, new_status.to_s)
    broadcast_status_change
  end

  private

  # Prepend the new meeting row to the index page list.
  def broadcast_created
    broadcast_prepend_to user,
      target: "meetings_list",
      partial: "meetings/meeting",
      locals: { meeting: self }
  end

  def broadcast_status_change
    broadcast_show_page
    broadcast_index_page
  end

  # Replace the full show page content area so the "in progress" placeholder
  # swaps to the completed 3-panel layout (or failure message) in real-time.
  def broadcast_show_page
    broadcast_replace_to self,
      target: "meeting_#{id}_content",
      partial: "meetings/show_content",
      locals: { meeting: self }
  end

  # Replace the meeting row on the index page so the status badge updates.
  def broadcast_index_page
    broadcast_replace_to user,
      target: ActionView::RecordIdentifier.dom_id(self),
      partial: "meetings/meeting",
      locals: { meeting: self }
  end
end
