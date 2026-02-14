class CompleteActionItemTool < RubyLLM::Tool
  description "Marks an action item as done or pending. " \
              "Use when the user says they finished a task or wants to undo completion."

  param :action_item_id, type: :integer, desc: "The ID of the action item to update"
  param :completed, type: :boolean, desc: "true to mark done, false to mark pending (default: true)", required: false

  def initialize(user)
    @user = user
  end

  def execute(action_item_id:, completed: true)
    item = Meeting::ActionItem
      .joins(:meeting)
      .where(meetings: { user_id: @user.id })
      .find(action_item_id)

    item.update!(completed: completed)

    status = completed ? "done" : "pending"
    "Marked action item as #{status}: #{item.description}"
  rescue ActiveRecord::RecordNotFound
    "Action item not found or access denied."
  end
end
