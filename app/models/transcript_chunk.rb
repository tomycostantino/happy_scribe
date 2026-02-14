class TranscriptChunk < ApplicationRecord
  belongs_to :transcript
  has_neighbors :embedding
  validates :content, presence: true
  validates :position, presence: true
end
