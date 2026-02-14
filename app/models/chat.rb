class Chat < ApplicationRecord
  acts_as_chat
  include Chat::Respondable

  belongs_to :user
  belongs_to :meeting, optional: true

  RAG_CHUNK_COUNT = 10

  # Tools available to the AI assistant. Tools that define button_label/button_prompt
  # also appear as quick-action buttons in the meeting chat UI.
  MEETING_TOOLS = [
    MeetingSummaryTool, ActionItemsTool, CreateActionItemTool, MeetingLookupTool,
    MeetingParticipantsTool, ContactLookupTool, ManageContactTool, SendActionItemEmailTool,
    SendSummaryEmailTool
  ].freeze

  # Returns [label, prompt] pairs for tools that define button metadata.
  def self.meeting_tool_buttons
    MEETING_TOOLS
      .select { |tool| tool.respond_to?(:button_label) && tool.respond_to?(:button_prompt) }
      .map { |tool| [ tool.button_label, tool.button_prompt ] }
  end

  TOOL_USE_RULES = <<~RULES
    CRITICAL — Tool usage rules (you MUST follow these):
    - NEVER pretend to call a tool or fabricate tool results. If you need information, actually call the tool.
    - NEVER say "let me look that up" or "I found..." without making a real tool call first.
    - If you need an email address, call meeting_participants or contact_lookup. Do not invent one.
    - If a tool returns an error or "not available", report exactly what the tool returned.
    - Do not narrate tool usage — just call the tools and respond with the real results.
  RULES

  EMAIL_RULES = <<~RULES
    Email rules:
    - When sending emails, ALWAYS use the meeting_participants tool first to get participants'
      email addresses. If the meeting has no participants linked, fall back to contact_lookup.
    - For action item emails, ALWAYS draft first so the user can review before sending.
    - For summary emails, send immediately — no draft or confirmation needed.
    - When the user provides an email, save it as a contact for future use.
  RULES

  ASSISTANT_SYSTEM_PROMPT = <<~PROMPT
    You are a meeting assistant with access to the user's complete meeting history.
    You can search meetings, review action items, create action items, and get summaries.

    You also manage the user's contacts and can send emails:
    - List meeting participants to see who was in a meeting and their email addresses
    - Look up contacts by name to find their email addresses
    - Save new contacts when you learn someone's email (so you remember it next time)
    - Draft and send action item emails to meeting participants
    - Send meeting summary emails to recipients (sends immediately, no draft needed)

    #{EMAIL_RULES}

    When answering questions:
    - Use tools to find specific information rather than guessing
    - Cite which meeting(s) your information comes from
    - For cross-meeting questions, search broadly then narrow down
    - When asked to extract or add action items, use the create tool to save them
    - Be concise and direct in your answers

    #{TOOL_USE_RULES}

    The user's meetings are transcribed from audio recordings.
    Today's date is %{date}.
  PROMPT

  MEETING_SYSTEM_PROMPT = <<~PROMPT
    You are a meeting assistant for the meeting "%{title}" (meeting_id: %{meeting_id}) from %{date}.

    IMPORTANT: When using tools that require a meeting_id parameter for THIS meeting, always use %{meeting_id}.
    You do NOT need to look up this meeting first — you already have its ID.

    %{transcript_section}

    You have tools available:
    - Look up other meetings by title, date, or participant
    - List meeting participants to see who was in this meeting and their email addresses
    - List action items across meetings (filter by assignee, status, or meeting)
    - Create and save action items for a meeting (one per tool call)
    - Get AI-generated summaries for any meeting
    - Look up contacts by name to find email addresses
    - Save new contacts when you learn someone's email
    - Draft and send action item emails (always draft first for user review)
    - Send meeting summary emails (sends immediately, no draft needed)

    When the user asks you to take action (e.g. extract action items, summarize, send emails),
    use your tools to save the results rather than just describing what you see.

    #{EMAIL_RULES}

    #{TOOL_USE_RULES}

    Be concise and direct. Cite specific quotes when relevant.
    Today's date is %{today}.
  PROMPT

  # Removes assistant messages with blank content left behind by failed API calls.
  # RubyLLM creates Message(content: '') before the API responds; if the call
  # fails, the empty message stays and causes Anthropic to reject all future
  # requests with "content missing".
  def cleanup_blank_assistant_messages!
    messages.where(role: "assistant").where(content: [ "", nil ]).destroy_all
  end

  # Sets up the agentic cross-meeting assistant with tools.
  # Used for standalone chats (no meeting attached).
  def with_assistant
    cleanup_blank_assistant_messages!

    prompt = ASSISTANT_SYSTEM_PROMPT % { date: Date.today.to_s }

    with_instructions(prompt, replace: true)
      .with_temperature(0.3)
      .with_tools(*build_tools)

    self
  end

  # Sets up the meeting-scoped assistant with RAG context and tools.
  # Used for chats attached to a specific meeting.
  # Always configures tools and system prompt — transcript chunks are
  # included when available but are not required. This ensures the LLM
  # can still use tools (summary, participants, email) even when the
  # transcript is still processing.
  def with_meeting_assistant(user_message: nil)
    cleanup_blank_assistant_messages!
    return self unless meeting

    transcript_section = build_transcript_section(user_message)

    prompt_text = MEETING_SYSTEM_PROMPT % {
      title: meeting.title,
      meeting_id: meeting.id,
      date: meeting.created_at.strftime("%B %d, %Y"),
      transcript_section: transcript_section,
      today: Date.today.to_s
    }

    with_instructions(prompt_text, replace: true)
      .with_temperature(0.3)
      .with_tools(*build_tools)
  end

  private

  def build_tools
    MEETING_TOOLS.map { |tool_class| tool_class.new(user) }
  end

  # Returns the transcript section for the meeting system prompt.
  # Includes relevant chunks when the transcript is ready, otherwise
  # tells the LLM the transcript isn't available yet.
  def build_transcript_section(user_message)
    transcript = meeting&.transcript

    unless transcript&.completed? && transcript.transcript_chunks.exists?
      return "The transcript for this meeting is not available yet (it may still be processing). " \
             "You can still use your tools to retrieve the summary, list participants, " \
             "manage action items, and send emails."
    end

    relevant_chunks = find_relevant_chunks(transcript, user_message || "")
    chunks_text = relevant_chunks.map(&:content).join("\n\n---\n\n")

    "Below are the most relevant sections of the transcript for the user's question.\n" \
    "Note: You are seeing selected portions, not the complete transcript.\n" \
    "If you cannot answer from the provided context, say so.\n\n" \
    "#{chunks_text}"
  end

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
