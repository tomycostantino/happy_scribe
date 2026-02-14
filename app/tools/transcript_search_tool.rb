class TranscriptSearchTool < RubyLLM::Tool
  description "Searches transcript content across all of the user's meetings. " \
              "Use this to find what was discussed in any meeting by keyword or topic. " \
              "Returns matching transcript excerpts with their meeting context."

  param :query, type: :string, desc: "Search term or topic to find in transcripts"
  param :limit, type: :integer, desc: "Maximum number of transcript chunks to return (default 10)", required: false

  def initialize(user)
    @user = user
  end

  def execute(query:, limit: 10)
    chunks = TranscriptChunk
      .joins(transcript: :meeting)
      .where(meetings: { user_id: @user.id })
      .where(transcripts: { status: "completed" })
      .where("to_tsvector('english', transcript_chunks.content) @@ plainto_tsquery('english', ?)", query)
      .order(Arel.sql("ts_rank(to_tsvector('english', transcript_chunks.content), plainto_tsquery('english', #{ActiveRecord::Base.connection.quote(query)})) DESC"))
      .limit(limit)
      .includes(transcript: :meeting)

    return "No transcript content found matching \"#{query}\"." if chunks.empty?

    chunks.map { |chunk| format_chunk(chunk) }.join("\n\n---\n\n")
  end

  private

  def format_chunk(chunk)
    meeting = chunk.transcript.meeting

    "Meeting: \"#{meeting.title}\" (ID: #{meeting.id}, #{meeting.created_at.strftime('%Y-%m-%d')})\n" \
    "Position: #{chunk.position}\n\n" \
    "#{chunk.content}"
  end
end
