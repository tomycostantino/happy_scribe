module HappyScribe
  module Transcription
    class SubmitJob < ApplicationJob
      queue_as :default

      retry_on HappyScribe::RateLimitError, wait: :polynomially_longer, attempts: 5

      def perform(meeting_id)
        HappyScribe::Transcription::Submit.perform_now(meeting_id)
      end
    end
  end
end
