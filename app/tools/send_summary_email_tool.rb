class SendSummaryEmailTool < RubyLLM::Tool
  description "Sends an email with the meeting summary to a recipient. " \
              "This sends immediately without requiring confirmation. " \
              "Use the meeting_participants or contact_lookup tool first to find email addresses."

  param :recipient_email, type: :string, desc: "Recipient's email address"
  param :recipient_name, type: :string, desc: "Recipient's name for the greeting", required: false
  param :meeting_id, type: :integer, desc: "Meeting ID to get the summary from"

  def initialize(user)
    @user = user
  end

  def execute(recipient_email:, meeting_id:, recipient_name: nil)
    meeting = find_meeting(meeting_id)
    return meeting if meeting.is_a?(String)

    summary = meeting.summary
    return "No summary available for \"#{meeting.title}\". The meeting may still be processing." unless summary

    subject = "Summary: #{meeting.title}"
    body = compose_body(meeting, summary, recipient_name)

    follow_up_email = meeting.follow_up_emails.create!(
      recipients: recipient_email,
      subject: subject,
      body: body,
      sent_at: Time.current
    )

    FollowUpMailer.summary(follow_up_email).deliver_later

    "Email sent to #{recipient_email} with summary of \"#{meeting.title}\""
  end

  private

  def find_meeting(meeting_id)
    @user.meetings.find(meeting_id)
  rescue ActiveRecord::RecordNotFound
    "Meeting not found or access denied."
  end

  def compose_body(meeting, summary, recipient_name)
    greeting = recipient_name.present? ? recipient_name : "there"
    meeting_date = meeting.created_at.to_date

    lines = []
    lines << "Hi #{greeting},"
    lines << ""
    lines << "Here is the summary from \"#{meeting.title}\" (#{meeting_date}):"
    lines << ""
    lines << summary.content.to_plain_text
    lines << ""
    lines << "---"
    lines << "Sent via Happy Scribe"

    lines.join("\n")
  end
end
