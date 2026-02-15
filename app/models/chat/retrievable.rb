# Retrieves relevant transcript chunks for RAG context in meeting chats.
#
# Uses full-text search (tsvector/tsquery) to find chunks matching the
# user's message, falling back to positional ordering when no text match
# is found.
module Chat::Retrievable
  extend ActiveSupport::Concern

  # Maximum number of transcript chunks fed into the meeting prompt as RAG context.
  RAG_CHUNK_COUNT = 10

  private

  # Returns the transcript section for the meeting system prompt.
  # Includes relevant chunks when the transcript is ready, otherwise
  # tells the LLM the transcript isn't available yet.
  def build_transcript_section(user_message)
    transcript = meeting&.transcript

    unless transcript&.completed? && transcript.transcript_chunks.exists?
      return "The transcript for this meeting is not available yet (it may still be processing). " \
             "You can still use your tools to retrieve the summary, list participants, " \
             "manage action items, and send emails."
    end

    relevant_chunks = find_relevant_chunks(transcript, user_message || "")
    chunks_text = relevant_chunks.map(&:content).join("\n\n---\n\n")

    "Below are the most relevant sections of the transcript for the user's question.\n" \
    "Note: You are seeing selected portions, not the complete transcript.\n" \
    "If you cannot answer from the provided context, say so.\n\n" \
    "#{chunks_text}"
  end

  def find_relevant_chunks(transcript, user_message)
    chunks = transcript.transcript_chunks

    if user_message.present?
      matched = chunks
        .where("to_tsvector('english', content) @@ plainto_tsquery('english', ?)", user_message)
        .order(Arel.sql("ts_rank(to_tsvector('english', content), plainto_tsquery('english', #{ActiveRecord::Base.connection.quote(user_message)})) DESC"))
        .limit(RAG_CHUNK_COUNT)

      return matched if matched.any?
    end

    # Fallback: return first chunks by position if no text match
    chunks.order(:position).limit(RAG_CHUNK_COUNT)
  end
end
