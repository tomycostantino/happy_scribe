class MeetingSummaryTool < RubyLLM::Tool
  description "Retrieves the AI-generated summary for a specific meeting. " \
              "If chatting within a meeting, use that meeting's ID directly. " \
              "Otherwise, use the meeting_lookup tool first to find the meeting ID."

  param :meeting_id, type: :integer, desc: "The meeting ID to get the summary for"

  def self.button_label
    "Summarize meeting"
  end

  def self.button_prompt
    "Summarize this meeting with key discussion points and decisions made."
  end

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
