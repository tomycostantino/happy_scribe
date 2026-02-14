module HappyScribe
  module Transcription
    class ImportJob < ApplicationJob
      queue_as :default

      retry_on HappyScribe::RateLimitError, wait: :polynomially_longer, attempts: 5

      def perform(user_id, happyscribe_id:)
        HappyScribe::Transcription::Import.perform_now(user_id, happyscribe_id: happyscribe_id)
      end
    end
  end
end
