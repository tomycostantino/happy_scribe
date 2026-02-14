module HappyScribe
  module Transcription
    class Import
      def self.perform_now(user_id, happyscribe_id:)
        user = User.find(user_id)
        client = HappyScribe::Client.new

        # 1. Fetch transcription metadata from HappyScribe
        result = client.retrieve_transcription(id: happyscribe_id)

        unless result["state"] == "automatic_done"
          raise HappyScribe::ApiError.new(
            "Transcription #{happyscribe_id} is not ready (state: #{result['state']})",
            status: 422
          )
        end

        # 2. Create local meeting + transcript (skips recording validation and auto-transcription)
        meeting = user.meetings.create!(
          title: result["name"],
          language: result["language"] || "en-US",
          source: :imported,
          status: :transcribing
        )

        meeting.create_transcript!(
          happyscribe_id: happyscribe_id,
          audio_length_seconds: result["audioLengthInSeconds"],
          status: :processing
        )

        # 3. Create export and kick off the existing fetch flow
        export = client.create_export(
          transcription_ids: [ happyscribe_id ],
          format: "json",
          show_speakers: true
        )
        meeting.transcript.update!(happyscribe_export_id: export["id"])

        HappyScribe::Transcription::ExportFetchJob.perform_later(meeting.id)

        meeting
      rescue HappyScribe::RateLimitError
        raise
      rescue => e
        Rails.logger.error("HappyScribe::Transcription::Import failed for happyscribe_id #{happyscribe_id}: #{e.message}")
        raise
      end
    end
  end
end
