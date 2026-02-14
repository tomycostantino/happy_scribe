class MeetingSummaryTool < RubyLLM::Tool
  description "Retrieves the AI-generated summary for a specific meeting. " \
              "Use the meeting_lookup tool first to find the meeting ID."

  param :meeting_id, type: :integer, desc: "The meeting ID to get the summary for"

  def initialize(user)
    @user = user
  end

  def execute(meeting_id:)
    meeting = @user.meetings.find(meeting_id)
    summary = meeting.summary

    return "No summary available yet for \"#{meeting.title}\"." unless summary

    "Summary for \"#{meeting.title}\" (#{meeting.created_at.strftime('%Y-%m-%d')}):\n\n" \
    "#{summary.content.to_plain_text}"
  end
end
