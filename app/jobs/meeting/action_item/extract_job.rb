class Meeting::ActionItem::ExtractJob < ApplicationJob
  queue_as :llm

  def perform(meeting_id)
    Meeting::ActionItem::Extract.perform_now(meeting_id)
  end
end
