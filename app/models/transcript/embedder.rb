# Chunks a transcript and persists the chunks for full-text search.
#
# Uses Transcript::Chunker to split segments into ~500-token chunks,
# then stores them as TranscriptChunk records. Chunks are searched
# using PostgreSQL full-text search (tsvector/tsquery) at query time.
#
# Failures are non-fatal — the chat system falls back to
# full-transcript mode if chunks are unavailable.
class Transcript::Embedder
  def self.perform_now(meeting_id)
    new(meeting_id).generate
  end

  def initialize(meeting_id)
    @meeting = Meeting.find(meeting_id)
    @transcript = @meeting.transcript
  end

  def generate
    return unless @transcript&.completed?

    chunks = Transcript::Chunker.perform_now(@transcript)
    return if chunks.empty?

    ActiveRecord::Base.transaction do
      @transcript.transcript_chunks.delete_all

      chunks.each do |chunk|
        @transcript.transcript_chunks.create!(
          content: chunk[:content],
          start_time: chunk[:start_time],
          end_time: chunk[:end_time],
          position: chunk[:position]
        )
      end
    end
  rescue StandardError => e
    Rails.logger.error("Transcript::Embedder failed for meeting #{@meeting.id}: #{e.message}")
  end
end
