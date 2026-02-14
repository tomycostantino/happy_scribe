class TranscriptSearchTool < RubyLLM::Tool
  description "Searches transcript content across all of the user's meetings. " \
              "Use this to find what was discussed in any meeting by keyword, topic, or meeting title. " \
              "You can search by content (query), by meeting title, or both. " \
              "Returns matching transcript excerpts with their meeting context."

  param :query, type: :string, desc: "Search term or topic to find in transcript content", required: false
  param :meeting_title, type: :string, desc: "Filter by meeting title (partial match). Use this when the user asks about a specific meeting by name.", required: false
  param :limit, type: :integer, desc: "Maximum number of transcript chunks to return (default 10)", required: false

  def initialize(user)
    @user = user
  end

  def execute(query: nil, meeting_title: nil, limit: 10)
    scope = TranscriptChunk
      .joins(transcript: :meeting)
      .where(meetings: { user_id: @user.id })
      .where(transcripts: { status: "completed" })

    scope = scope.where("meetings.title ILIKE ?", "%#{meeting_title}%") if meeting_title.present?

    if query.present?
      scope = scope
        .where("to_tsvector('english', transcript_chunks.content) @@ plainto_tsquery('english', ?)", query)
        .order(Arel.sql("ts_rank(to_tsvector('english', transcript_chunks.content), plainto_tsquery('english', #{ActiveRecord::Base.connection.quote(query)})) DESC"))
    else
      scope = scope.order("meetings.created_at DESC, transcript_chunks.position ASC")
    end

    chunks = scope.limit(limit).includes(transcript: :meeting)

    search_desc = [ query, meeting_title ].compact.join(", ")
    return "No transcript content found matching \"#{search_desc}\"." if chunks.empty?

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
