class SendActionItemEmailTool < RubyLLM::Tool
  description "Drafts or sends an email with action items from a meeting. " \
              "First call with action 'draft' to preview, then 'send' to deliver. " \
              "Always draft first so the user can review before sending."

  param :action, type: :string, desc: "Either 'draft' to preview or 'send' to deliver the email"
  param :recipient_email, type: :string, desc: "Recipient's email address"
  param :recipient_name, type: :string, desc: "Recipient's name for the greeting", required: false
  param :meeting_id, type: :integer, desc: "Meeting ID to get action items from"
  param :assignee, type: :string, desc: "Filter action items by assignee name (optional)", required: false

  def initialize(user)
    @user = user
  end

  def execute(action:, recipient_email:, meeting_id:, recipient_name: nil, assignee: nil)
    case action
    when "draft"
      draft(meeting_id: meeting_id, recipient_email: recipient_email, recipient_name: recipient_name, assignee: assignee)
    when "send"
      send_email(meeting_id: meeting_id, recipient_email: recipient_email, recipient_name: recipient_name, assignee: assignee)
    else
      "Invalid action '#{action}'. Use 'draft' to preview or 'send' to deliver."
    end
  end

  private

  def draft(meeting_id:, recipient_email:, recipient_name:, assignee:)
    meeting = find_meeting(meeting_id)
    return meeting if meeting.is_a?(String)

    items = fetch_action_items(meeting, assignee)
    return "No action items found for this meeting." if items.empty?

    subject = compose_subject(meeting, assignee)
    body = compose_body(meeting, items, recipient_name)

    "Subject: #{subject}\n\n#{body}"
  end

  def send_email(meeting_id:, recipient_email:, recipient_name:, assignee:)
    meeting = find_meeting(meeting_id)
    return meeting if meeting.is_a?(String)

    items = fetch_action_items(meeting, assignee)
    return "No action items found for this meeting." if items.empty?

    subject = compose_subject(meeting, assignee)
    body = compose_body(meeting, items, recipient_name)

    follow_up_email = meeting.follow_up_emails.create!(
      recipients: recipient_email,
      subject: subject,
      body: body,
      sent_at: Time.current
    )

    FollowUpMailer.action_items(follow_up_email).deliver_later

    "Email sent to #{recipient_email} with #{items.size} action items from '#{meeting.title}'"
  end

  def find_meeting(meeting_id)
    @user.meetings.find(meeting_id)
  rescue ActiveRecord::RecordNotFound
    "Meeting not found or access denied."
  end

  def fetch_action_items(meeting, assignee)
    items = meeting.action_items
    items = items.where("assignee ILIKE ?", assignee) if assignee.present?
    items.to_a
  end

  def compose_subject(meeting, assignee)
    if assignee.present?
      "Action items for #{assignee} from #{meeting.title}"
    else
      "Action items from #{meeting.title}"
    end
  end

  def compose_body(meeting, items, recipient_name)
    greeting = recipient_name.present? ? recipient_name : "there"
    meeting_date = meeting.created_at.to_date

    lines = []
    lines << "Hi #{greeting},"
    lines << ""
    lines << "Here are the action items from \"#{meeting.title}\" (#{meeting_date}):"
    lines << ""

    items.each do |item|
      line = "- #{item.description}"
      annotations = []
      annotations << "due: #{item.due_date}" if item.due_date.present?
      annotations << "assigned to: #{item.assignee}" if item.assignee.present?
      line += " (#{annotations.join(", ")})" if annotations.any?
      lines << line
    end

    lines << ""
    lines << "---"
    lines << "Sent via Happy Scribe"

    lines.join("\n")
  end
end
