class Chat < ApplicationRecord
  acts_as_chat

  belongs_to :user
  belongs_to :meeting, optional: true

  RAG_CHUNK_COUNT = 10

  MEETING_SYSTEM_PROMPT = <<~PROMPT
    You are a meeting assistant for the meeting "%{title}" from %{date}.

    Below are the most relevant sections of the transcript for the user's question.
    Note: You are seeing selected portions, not the complete transcript.
    If you cannot answer from the provided context, say so.

    %{chunks}

    Be concise and direct. Cite specific quotes when relevant.
    Today's date is %{today}.
  PROMPT

  def with_meeting_assistant(user_message: nil)
    return self unless meeting&.transcript&.completed?
    return self unless meeting.transcript.transcript_chunks.exists?

    relevant_chunks = find_relevant_chunks(meeting.transcript, user_message || "")
    chunks_text = relevant_chunks.map(&:content).join("\n\n---\n\n")

    prompt_text = MEETING_SYSTEM_PROMPT % {
      title: meeting.title,
      date: meeting.created_at.strftime("%B %d, %Y"),
      chunks: chunks_text,
      today: Date.today.to_s
    }

    with_instructions(prompt_text, replace: true).with_temperature(0.3)
  end

  private

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
