class ActionItemsTool < RubyLLM::Tool
  description "Lists action items extracted from meetings. " \
              "Can filter by assignee, completion status, or specific meeting."

  param :assignee, type: :string, desc: "Filter by person assigned to the task", required: false
  param :completed, type: :boolean, desc: "Filter: true for done, false for pending", required: false
  param :meeting_id, type: :integer, desc: "Filter by specific meeting ID", required: false
  param :limit, type: :integer, desc: "Maximum results (default 20)", required: false

  def initialize(user)
    @user = user
  end

  def execute(assignee: nil, completed: nil, meeting_id: nil, limit: 20)
    scope = Meeting::ActionItem.joins(:meeting).where(meetings: { user_id: @user.id })

    scope = scope.where("meeting_action_items.assignee ILIKE ?", "%#{assignee}%") if assignee.present?
    scope = scope.where(completed: completed) unless completed.nil?
    scope = scope.where(meeting_id: meeting_id) if meeting_id

    items = scope.includes(:meeting).order(created_at: :desc).limit(limit)

    return "No action items found." if items.empty?

    items.map { |ai| format_action_item(ai) }.join("\n\n")
  end

  private

  def format_action_item(item)
    status = item.completed? ? "[DONE]" : "[PENDING]"
    assignee = item.assignee.present? ? " (assigned to: #{item.assignee})" : ""
    due = item.due_date.present? ? " | Due: #{item.due_date}" : ""

    "#{status} #{item.description}#{assignee}#{due}\n" \
    "  From: \"#{item.meeting.title}\" (#{item.meeting.created_at.strftime('%Y-%m-%d')})"
  end
end
