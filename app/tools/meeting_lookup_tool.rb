class MeetingLookupTool < RubyLLM::Tool
  description "Finds meetings by title, date range, or participant/speaker. " \
              "Use this to identify which meetings to investigate further."

  param :query, type: :string, desc: "Search term for meeting titles", required: false
  param :after, type: :string, desc: "ISO date — only meetings after this date (e.g., '2026-01-15')", required: false
  param :before, type: :string, desc: "ISO date — only meetings before this date", required: false
  param :participant, type: :string, desc: "Speaker name to filter by", required: false
  param :limit, type: :integer, desc: "Maximum results (default 10)", required: false

  def initialize(user)
    @user = user
  end

  def execute(query: nil, after: nil, before: nil, participant: nil, limit: 10)
    scope = @user.meetings.where.not(status: [ :uploading, :failed ])

    scope = scope.where("title ILIKE ?", "%#{query}%") if query.present?
    scope = scope.where("meetings.created_at >= ?", Date.parse(after)) if after.present?
    scope = scope.where("meetings.created_at <= ?", Date.parse(before).end_of_day) if before.present?

    if participant.present?
      scope = scope.joins(transcript: :transcript_segments)
                   .where("transcript_segments.speaker ILIKE ?", "%#{participant}%")
                   .distinct
    end

    meetings = scope.order(created_at: :desc).limit(limit)

    return "No meetings found matching your criteria." if meetings.empty?

    meetings.map { |m| format_meeting(m) }.join("\n\n")
  end

  private

  def format_meeting(meeting)
    speakers = meeting.transcript&.transcript_segments
      &.select(:speaker)&.distinct&.pluck(:speaker)&.compact || []

    "ID: #{meeting.id} | \"#{meeting.title}\"\n" \
    "Date: #{meeting.created_at.strftime('%Y-%m-%d %H:%M')}\n" \
    "Status: #{meeting.status}\n" \
    "Speakers: #{speakers.any? ? speakers.join(', ') : 'Unknown'}"
  end
end
