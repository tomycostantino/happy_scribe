class Transcript < ApplicationRecord
  belongs_to :meeting
  has_many :transcript_segments, dependent: :destroy

  has_rich_text :content

  enum :status, {
    pending: "pending",
    processing: "processing",
    completed: "completed",
    failed: "failed"
  }, default: :pending

  # Parses HappyScribe JSON export and creates TranscriptSegments.
  #
  # Real format is an array of speaker segments:
  #   [{"speaker": "Speaker 1", "words": [{"text": "Hello", "data_start": 0.0, "data_end": 1.0}],
  #     "data_start": 0.0, "data_end": 1.0}]
  def parse_happyscribe_export(data)
    transcript_segments.destroy_all

    # data is an array of speaker segments from HappyScribe
    segments = data.is_a?(Array) ? data : []
    return if segments.empty?

    segments.each_with_index do |segment, i|
      words = segment["words"] || []
      text = words.map { |w| w["text"] }.join(" ")

      transcript_segments.create!(
        speaker: segment["speaker"],
        content: text.strip,
        start_time: segment["data_start"],
        end_time: segment["data_end"],
        position: i
      )
    end
  end

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
