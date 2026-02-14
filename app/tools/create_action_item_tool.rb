class CreateActionItemTool < RubyLLM::Tool
  description "Creates an action item for a meeting. Call once per action item. " \
              "Use when the user asks to extract, add, or save action items."

  param :meeting_id,  type: :integer, desc: "The meeting ID to add the action item to"
  param :description, type: :string,  desc: "What needs to be done"
  param :assignee,    type: :string,  desc: "Person responsible for the task", required: false
  param :due_date,    type: :string,  desc: "Due date in YYYY-MM-DD format", required: false

  def self.button_label
    "Extract & save action items"
  end

  def self.button_prompt
    "Extract all action items from this meeting and save them as action items."
  end

  def initialize(user)
    @user = user
  end

  def execute(meeting_id:, description:, assignee: nil, due_date: nil)
    meeting = @user.meetings.find(meeting_id)

    desc = description.strip
    existing = meeting.action_items.where("description ILIKE ?", desc)
    return "Action item already exists: #{existing.first.description}" if existing.exists?

    parsed_due_date = due_date.present? ? Date.parse(due_date) : nil

    item = meeting.action_items.create!(
      description: desc,
      assignee: assignee&.strip.presence,
      due_date: parsed_due_date
    )

    result = "Created action item: #{item.description}"
    result += " (assigned to #{item.assignee})" if item.assignee.present?
    result += " due #{item.due_date}" if item.due_date.present?
    result
  rescue ActiveRecord::RecordNotFound
    "Meeting not found or access denied."
  rescue Date::Error
    "Invalid due date format. Use YYYY-MM-DD."
  rescue ActiveRecord::RecordInvalid => e
    "Failed to create action item: #{e.message}"
  end
end
