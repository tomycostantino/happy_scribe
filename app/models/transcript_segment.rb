class TranscriptSegment < ApplicationRecord
  belongs_to :transcript

  validates :content, presence: true
  validates :position, presence: true

  default_scope { order(:position) }
end
