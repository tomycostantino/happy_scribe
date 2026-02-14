class CompleteActionItemTool < RubyLLM::Tool
  description "Marks an action item as done or pending. " \
              "Use when the user says they finished a task or wants to undo completion. " \
              "Provide either action_item_id or description + meeting_id to identify the item."

  param :action_item_id, type: :integer, desc: "The ID of the action item to update", required: false
  param :description, type: :string, desc: "Text to match against the action item description (case-insensitive substring match)", required: false
  param :meeting_id, type: :integer, desc: "The meeting ID to search within (used with description)", required: false
  param :completed, type: :boolean, desc: "true to mark done, false to mark pending (default: true)", required: false

  def initialize(user)
    @user = user
  end

  def execute(action_item_id: nil, description: nil, meeting_id: nil, completed: true)
    item = find_action_item(action_item_id, description, meeting_id)
    return item if item.is_a?(String) # error message

    item.update!(completed: completed)

    status = completed ? "done" : "pending"
    "Marked action item as #{status}: #{item.description}"
  rescue ActiveRecord::RecordNotFound
    "Action item not found or access denied."
  end

  private

  def find_action_item(action_item_id, description, meeting_id)
    scope = Meeting::ActionItem.joins(:meeting).where(meetings: { user_id: @user.id })

    if action_item_id
      scope.find(action_item_id)
    elsif description.present?
      scope = scope.where(meeting_id: meeting_id) if meeting_id
      item = scope.where("meeting_action_items.description ILIKE ?", "%#{description}%").first
      item || "Action item not found or access denied."
    else
      "Please provide either an action_item_id or a description to identify the action item."
    end
  end
end
