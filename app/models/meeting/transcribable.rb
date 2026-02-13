module Meeting::Transcribable
  extend ActiveSupport::Concern

  included do
    after_create_commit :start_transcription
  end

  private

  def start_transcription
    create_transcript!(status: :pending)
    HappyScribe::Transcription::SubmitJob.perform_later(id)
  end
end
