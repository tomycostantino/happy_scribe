# Configures the AI tools available to the chat assistant.
#
# Defines which tool classes the LLM can invoke and provides helpers
# for building tool instances and exposing quick-action buttons in the UI.
module Chat::Toolable
  extend ActiveSupport::Concern

  included do
    # Tools available to the AI assistant. Tools that define button_label/button_prompt
    # also appear as quick-action buttons in the meeting chat UI.
    MEETING_TOOLS = [
      MeetingSummaryTool, ActionItemsTool, CreateActionItemTool, CompleteActionItemTool,
      MeetingLookupTool, MeetingParticipantsTool, ContactLookupTool, ManageContactTool,
      SendActionItemEmailTool, SendSummaryEmailTool, TranscriptSearchTool
    ].freeze
  end

  class_methods do
    # Returns [label, prompt] pairs for tools that define button metadata.
    def meeting_tool_buttons
      MEETING_TOOLS
        .select { |tool| tool.respond_to?(:button_label) && tool.respond_to?(:button_prompt) }
        .map { |tool| [ tool.button_label, tool.button_prompt ] }
    end
  end

  private

  def build_tools
    MEETING_TOOLS.map { |tool_class| tool_class.new(user) }
  end
end
