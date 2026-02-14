module Transcript::Parseable
  extend ActiveSupport::Concern

  # Parses HappyScribe JSON export and creates TranscriptSegments.
  #
  # Real format is an array of speaker segments:
  #   [{"speaker": "Speaker 1", "words": [{"text": "Hello", "data_start": 0.0, "data_end": 1.0}],
  #     "data_start": 0.0, "data_end": 1.0}]
  def parse_happyscribe_export(data)
    segments = data.is_a?(Array) ? data : []
    return if segments.empty?

    transaction do
      transcript_segments.delete_all

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
  end
end
