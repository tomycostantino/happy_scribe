class TranscriptSegment < ApplicationRecord
  belongs_to :transcript

  validates :content, presence: true
  validates :position, presence: true

  scope :ordered, -> { order(:position) }
end
