# Splits a transcript into chunks suitable for embedding.
#
# Chunks respect segment boundaries (never splits mid-segment) and include
# 1-segment overlap between consecutive chunks for context continuity.
# Each chunk's content uses the same "Speaker [HH:MM:SS]: text" format
# as Transcript::Formattable.
class Transcript::Chunker
  CHARS_PER_TOKEN = 4
  DEFAULT_MAX_TOKENS = 500

  def self.perform_now(transcript, max_tokens: DEFAULT_MAX_TOKENS)
    new(transcript, max_tokens:).chunk
  end

  def initialize(transcript, max_tokens: DEFAULT_MAX_TOKENS)
    @transcript = transcript
    @max_chars = max_tokens * CHARS_PER_TOKEN
  end

  # Returns array of hashes: { content:, start_time:, end_time:, position: }
  def chunk
    segments = @transcript.transcript_segments.ordered.to_a
    return [] if segments.empty?

    chunks = []
    current_segments = []
    current_length = 0

    segments.each do |segment|
      formatted = format_segment(segment)
      segment_length = formatted.length

      if current_segments.any? && (current_length + segment_length) > @max_chars
        chunks << build_chunk(current_segments, chunks.size)

        # Overlap: start next chunk with the last segment of the previous chunk
        overlap = current_segments.last
        current_segments = [ overlap ]
        current_length = format_segment(overlap).length
      end

      current_segments << segment
      current_length += segment_length
    end

    # Final chunk
    chunks << build_chunk(current_segments, chunks.size) if current_segments.any?

    chunks
  end

  private

  def format_segment(segment)
    timestamp = format_timestamp(segment.start_time)
    "#{segment.speaker} [#{timestamp}]: #{segment.content}"
  end

  def format_timestamp(seconds)
    return "00:00:00" if seconds.nil?
    seconds = seconds.to_i
    "%02d:%02d:%02d" % [ seconds / 3600, (seconds % 3600) / 60, seconds % 60 ]
  end

  def build_chunk(segments, position)
    {
      content: segments.map { |s| format_segment(s) }.join("\n\n"),
      start_time: segments.first.start_time,
      end_time: segments.last.end_time,
      position: position
    }
  end
end
