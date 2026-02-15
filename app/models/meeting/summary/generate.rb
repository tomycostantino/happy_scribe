# Generates an AI-powered summary for a meeting's transcript.
#
# Uses RubyLLM to call Claude with a structured summarization prompt.
# Creates a Meeting::Summary record with rich text content.
# Marks the meeting as failed if the AI call errors out.
class Meeting::Summary::Generate
  SYSTEM_PROMPT = <<~PROMPT
    You are a meeting summarizer. Given a meeting transcript with speaker labels and timestamps,
    produce a clear, structured summary.

    Your summary must include these sections:

    ## Meeting Overview
    2-3 sentences describing what the meeting was about.

    ## Key Discussion Points
    Bullet list of the main topics discussed.

    ## Decisions Made
    Bullet list of any decisions that were made. If none, write "No explicit decisions were made."

    ## Next Steps
    Bullet list of agreed-upon next steps. If none, write "No specific next steps were identified."

    Be concise. Use the speakers' actual names/labels. Do not invent information not present in the transcript.
  PROMPT

  def self.perform_now(meeting_id)
    new(meeting_id).generate
  end

  def initialize(meeting_id)
    @meeting = Meeting.find(meeting_id)
  end

  def generate
    return if @meeting.summary.present?

    formatted_text = @meeting.transcript.formatted_text
    model = Rails.application.config.ai.default_model

    chat = RubyLLM.chat(model: model)
    response = chat.ask("#{SYSTEM_PROMPT}\n\n---\n\nTranscript:\n\n#{formatted_text}")

    @meeting.create_summary!(
      content: response.content,
      model_used: model
    )

    @meeting.check_processing_complete!
  rescue StandardError => e
    Rails.logger.error("Meeting::Summary::Generate failed for meeting #{@meeting.id}: #{e.message}")
    @meeting.transition_status!(:failed)
  end
end
