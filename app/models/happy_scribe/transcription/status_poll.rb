module HappyScribe
  module Transcription
    class StatusPoll
      MAX_POLLS = 360
      BASE_WAIT = 5.seconds
      MAX_WAIT = 30.seconds

      def self.perform_now(meeting_id, poll_count: 0)
        meeting = Meeting.find(meeting_id)
        transcript = meeting.transcript
        client = HappyScribe::Client.new

        result = client.retrieve_transcription(id: transcript.happyscribe_id)

        case result["state"]
        when "automatic_done"
          transcript.update!(audio_length_seconds: result["audioLengthInSeconds"])

          export = client.create_export(
            transcription_ids: [ transcript.happyscribe_id ],
            format: "json",
            show_speakers: true
          )
          transcript.update!(happyscribe_export_id: export["id"])

          HappyScribe::Transcription::ExportFetchJob.perform_later(meeting.id)
        when "failed", "locked"
          transcript.update!(status: :failed)
          meeting.update!(status: :failed)
        else
          if poll_count >= MAX_POLLS
            transcript.update!(status: :failed)
            meeting.update!(status: :failed)
          else
            wait = [ BASE_WAIT * (1.5**[ poll_count, 10 ].min), MAX_WAIT ].min
            HappyScribe::Transcription::StatusPollJob.set(wait: wait).perform_later(meeting.id, poll_count: poll_count + 1)
          end
        end
      rescue => e
        meeting = Meeting.find(meeting_id)
        meeting.update!(status: :failed)
        meeting.transcript&.update!(status: :failed)
        Rails.logger.error("HappyScribe::Transcription::StatusPoll failed for meeting #{meeting_id}: #{e.message}")
      end
    end
  end
end
