class Chat < ApplicationRecord
  acts_as_chat

  belongs_to :user
  belongs_to :meeting, optional: true

  MEETING_SYSTEM_PROMPT = <<~PROMPT
    You are a meeting assistant for the meeting "%{title}" from %{date}.

    Here is the full transcript:

    %{transcript}

    Answer questions about this meeting based on the transcript above.
    Be concise and direct. Cite specific quotes when relevant.
    Today's date is %{today}.
  PROMPT

  def with_meeting_assistant
    return self unless meeting&.transcript&.completed?

    with_instructions(
      MEETING_SYSTEM_PROMPT % {
        title: meeting.title,
        date: meeting.created_at.strftime("%B %d, %Y"),
        transcript: meeting.transcript.formatted_text,
        today: Date.today.to_s
      },
      replace: true
    ).with_temperature(0.3)
  end
end
