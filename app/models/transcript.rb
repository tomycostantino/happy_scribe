class Transcript < ApplicationRecord
  belongs_to :meeting
  has_many :transcript_segments, dependent: :destroy
  has_many :transcript_chunks, dependent: :destroy

  has_rich_text :content

  enum :status, {
    pending: "pending",
    processing: "processing",
    completed: "completed",
    failed: "failed"
  }, default: :pending

  # Returns the full transcript as formatted text with speaker labels
  def formatted_text
    transcript_segments.order(:position).map do |segment|
      timestamp = format_timestamp(segment.start_time)
      "#{segment.speaker} [#{timestamp}]: #{segment.content}"
    end.join("\n\n")
  end

  private

  def format_timestamp(seconds)
    return "00:00:00" if seconds.nil?
    Time.at(seconds).utc.strftime("%H:%M:%S")
  end
end
