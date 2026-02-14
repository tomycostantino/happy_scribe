module HappyScribe
  module Transcription
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

          ActiveRecord::Base.transaction do
            transcript.update!(raw_response: parsed)
            transcript.parse_happyscribe_export(parsed)
            transcript.update!(status: :completed)
            meeting.update!(status: :transcribed)
          end

          # Generate embeddings for RAG search (non-blocking, non-fatal)
          Transcript::EmbedderJob.perform_later(meeting.id)
        when "failed", "expired"
          transcript.update!(status: :failed)
          meeting.update!(status: :failed)
        else
          if poll_count >= MAX_POLLS
            transcript.update!(status: :failed)
            meeting.update!(status: :failed)
          else
            HappyScribe::Transcription::ExportFetchJob.set(wait: 3.seconds).perform_later(meeting.id, poll_count: poll_count + 1)
          end
        end
      rescue => e
        meeting = Meeting.find(meeting_id)
        meeting.update!(status: :failed)
        meeting.transcript&.update!(status: :failed)
        Rails.logger.error("HappyScribe::Transcription::ExportFetch failed for meeting #{meeting_id}: #{e.message}")
      end
    end
  end
end
