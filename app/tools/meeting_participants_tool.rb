class MeetingParticipantsTool < RubyLLM::Tool
  description "Lists participants linked to a meeting with their contact info and speaker labels. " \
              "Use this to find out who was in a meeting and their email addresses before sending emails."

  param :meeting_id, type: :integer, desc: "The meeting ID to get participants for"

  def initialize(user)
    @user = user
  end

  def execute(meeting_id:)
    meeting = @user.meetings.find(meeting_id)
    participants = meeting.participants.includes(:contact)

    return "No participants linked to this meeting yet." if participants.empty?

    lines = [ "Participants for \"#{meeting.title}\":" ]
    lines << ""

    participants.each do |p|
      line = "- #{p.contact.name} <#{p.contact.email}>"
      line += " (#{p.role})" if p.organizer?
      line += " — Speaker: #{p.speaker_label}" if p.speaker_label.present?
      lines << line
    end

    lines.join("\n")
  end
end
