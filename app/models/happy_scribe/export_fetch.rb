module HappyScribe
  class ExportFetch
    MAX_POLLS = 60

    def self.perform_now(meeting_id, poll_count: 0)
      meeting = Meeting.find(meeting_id)
      transcript = meeting.transcript
      client = HappyScribe::Client.new

      result = client.retrieve_export(id: transcript.happyscribe_export_id)

      case result["state"]
      when "ready"
        raw_json = client.download(result["download_link"])
        parsed = JSON.parse(raw_json)

        transcript.update!(raw_response: parsed)
        transcript.parse_happyscribe_export(parsed)
        transcript.update!(status: :completed)
        meeting.update!(status: :transcribed)
      when "failed", "expired"
        transcript.update!(status: :failed)
        meeting.update!(status: :failed)
      else
        if poll_count >= MAX_POLLS
          transcript.update!(status: :failed)
          meeting.update!(status: :failed)
        else
          FetchExportJob.set(wait: 3.seconds).perform_later(meeting.id, poll_count: poll_count + 1)
        end
      end
    rescue => e
      Meeting.find(meeting_id).update!(status: :failed)
      Rails.logger.error("HappyScribe::ExportFetch failed for meeting #{meeting_id}: #{e.message}")
    end
  end
end
