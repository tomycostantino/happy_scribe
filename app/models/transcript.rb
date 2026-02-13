class Transcript < ApplicationRecord
  include Parseable
  include Formattable

  belongs_to :meeting
  has_many :transcript_segments, dependent: :destroy

  has_rich_text :content

  enum :status, {
    pending: "pending",
    processing: "processing",
    completed: "completed",
    failed: "failed"
  }, default: :pending
end
