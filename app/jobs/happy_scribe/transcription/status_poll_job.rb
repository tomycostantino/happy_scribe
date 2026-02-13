module HappyScribe
  module Transcription
    class StatusPollJob < ApplicationJob
      queue_as :default

      def perform(meeting_id, poll_count: 0)
        HappyScribe::Transcription::StatusPoll.perform_now(meeting_id, poll_count:)
      end
    end
  end
end
