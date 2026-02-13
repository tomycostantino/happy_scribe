class Meeting < ApplicationRecord
  include Transcribable

  belongs_to :user
  has_one :transcript, dependent: :destroy
  has_one_attached :recording

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
  validate :recording_attached

  # TODO: Re-add when Summary and ActionItem models are created
  # def check_processing_complete!
  #   return unless summary.present? && action_items.any?
  #   update!(status: :completed)
  # end

  private

  def recording_attached
    errors.add(:recording, "must be attached") unless recording.attached?
  end
end
