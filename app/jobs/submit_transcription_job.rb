class SubmitTranscriptionJob < ApplicationJob
  queue_as :default

  retry_on HappyScribe::RateLimitError, wait: :polynomially_longer, attempts: 5

  def perform(meeting_id)
    HappyScribe::Submission.perform_now(meeting_id)
  end
end
