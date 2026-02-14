class Meeting::Summary::GenerateJob < ApplicationJob
  queue_as :llm

  def perform(meeting_id)
    Meeting::Summary::Generate.perform_now(meeting_id)
  end
end
