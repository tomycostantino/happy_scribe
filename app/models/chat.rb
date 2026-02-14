class Chat < ApplicationRecord
  acts_as_chat

  belongs_to :user
  belongs_to :meeting, optional: true

  RAG_CHUNK_COUNT = 10

  # Tools that expose quick-action buttons for the meeting chat UI.
  MEETING_TOOLS = [ MeetingSummaryTool, ActionItemsTool, CreateActionItemTool, MeetingLookupTool ].freeze

  # Returns [label, prompt] pairs for tools that define button metadata.
  def self.meeting_tool_buttons
    MEETING_TOOLS
      .select { |tool| tool.respond_to?(:button_label) && tool.respond_to?(:button_prompt) }
      .map { |tool| [ tool.button_label, tool.button_prompt ] }
  end

  ASSISTANT_SYSTEM_PROMPT = <<~PROMPT
    You are a meeting assistant with access to the user's complete meeting history.
    You can search meetings, review action items, create action items, and get summaries.

    When answering questions:
    - Use tools to find specific information rather than guessing
    - Cite which meeting(s) your information comes from
    - For cross-meeting questions, search broadly then narrow down
    - When asked to extract or add action items, use the create tool to save them
    - Be concise and direct in your answers

    The user's meetings are transcribed from audio recordings.
    Today's date is %{date}.
  PROMPT

  MEETING_SYSTEM_PROMPT = <<~PROMPT
    You are a meeting assistant for the meeting "%{title}" from %{date}.

    Below are the most relevant sections of the transcript for the user's question.
    Note: You are seeing selected portions, not the complete transcript.
    If you cannot answer from the provided context, say so.

    %{chunks}

    You also have tools available:
    - Look up other meetings by title, date, or participant
    - List action items across meetings (filter by assignee, status, or meeting)
    - Create and save action items for a meeting (one per tool call)
    - Get AI-generated summaries for any meeting

    When the user asks you to take action (e.g. extract action items, summarize),
    use your tools to save the results rather than just describing what you see.

    Be concise and direct. Cite specific quotes when relevant.
    Today's date is %{today}.
  PROMPT

  # Sets up the agentic cross-meeting assistant with tools.
  # Used for standalone chats (no meeting attached).
  def with_assistant
    prompt = ASSISTANT_SYSTEM_PROMPT % { date: Date.today.to_s }

    with_instructions(prompt, replace: true)
      .with_temperature(0.3)
      .with_tools(
        MeetingLookupTool.new(user),
        ActionItemsTool.new(user),
        CreateActionItemTool.new(user),
        MeetingSummaryTool.new(user)
      )

    self
  end

  # Sets up the meeting-scoped assistant with RAG context.
  # Used for chats attached to a specific meeting.
  def with_meeting_assistant(user_message: nil)
    return self unless meeting&.transcript&.completed?
    return self unless meeting.transcript.transcript_chunks.exists?

    relevant_chunks = find_relevant_chunks(meeting.transcript, user_message || "")
    chunks_text = relevant_chunks.map(&:content).join("\n\n---\n\n")

    prompt_text = MEETING_SYSTEM_PROMPT % {
      title: meeting.title,
      date: meeting.created_at.strftime("%B %d, %Y"),
      chunks: chunks_text,
      today: Date.today.to_s
    }

    with_instructions(prompt_text, replace: true)
      .with_temperature(0.3)
      .with_tools(
        MeetingLookupTool.new(user),
        ActionItemsTool.new(user),
        CreateActionItemTool.new(user),
        MeetingSummaryTool.new(user)
      )
  end

  private

  def find_relevant_chunks(transcript, user_message)
    chunks = transcript.transcript_chunks

    if user_message.present?
      matched = chunks
        .where("to_tsvector('english', content) @@ plainto_tsquery('english', ?)", user_message)
        .order(Arel.sql("ts_rank(to_tsvector('english', content), plainto_tsquery('english', #{ActiveRecord::Base.connection.quote(user_message)})) DESC"))
        .limit(RAG_CHUNK_COUNT)

      return matched if matched.any?
    end

    # Fallback: return first chunks by position if no text match
    chunks.order(:position).limit(RAG_CHUNK_COUNT)
  end
end
