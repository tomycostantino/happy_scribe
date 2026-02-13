class FetchExportJob < ApplicationJob
  queue_as :default

  def perform(meeting_id, poll_count: 0)
    HappyScribe::ExportFetch.perform_now(meeting_id, poll_count:)
  end
end
