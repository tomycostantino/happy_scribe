class Meeting < ApplicationRecord
  include Recordable
  include Transcribable

  belongs_to :user
  has_one :transcript, dependent: :destroy

  enum :status, {
    uploading: "uploading",
    transcribing: "transcribing",
    transcribed: "transcribed",
    processing: "processing",
    completed: "completed",
    failed: "failed"
  }, default: :uploading

  validates :title, presence: true
  validates :language, presence: true

  # TODO: Re-add when Summary and ActionItem models are created
  # def check_processing_complete!
  #   return unless summary.present? && action_items.any?
  #   update!(status: :completed)
  # end
end
