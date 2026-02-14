# Extracts action items from a meeting transcript using AI.
#
# Uses RubyLLM to call Claude with a structured extraction prompt.
# Parses the JSON response and creates Meeting::ActionItem records.
# Marks the meeting as failed if the AI call errors out.
class Meeting::ActionItem::Extract
  SYSTEM_PROMPT = <<~PROMPT
    You are a meeting action item extractor. Given a meeting transcript with speaker labels,
    extract all action items mentioned.

    Return a JSON array of action items. Each item should have:
    - "description": A clear, concise description of the action item
    - "assignee": The person responsible (use their speaker label or name if mentioned). Use null if unclear.
    - "due_date": The due date in YYYY-MM-DD format if mentioned. Use null if no date was mentioned.

    Rules:
    - Only extract concrete, actionable items (not vague intentions)
    - Use the exact speaker names/labels from the transcript
    - Return ONLY the JSON array, no other text
    - If there are no action items, return an empty array: []
  PROMPT

  def self.perform_now(meeting_id)
    new(meeting_id).extract
  end

  def initialize(meeting_id)
    @meeting = Meeting.find(meeting_id)
  end

  def extract
    return if @meeting.action_items.any?

    formatted_text = @meeting.transcript.formatted_text
    model = Rails.application.config.ai.default_model

    chat = RubyLLM.chat(model: model)
    response = chat.ask("#{SYSTEM_PROMPT}\n\n---\n\nTranscript:\n\n#{formatted_text}")

    items = parse_json(response.content)

    items.each do |item|
      @meeting.action_items.create!(
        description: item["description"],
        assignee: item["assignee"],
        due_date: parse_date(item["due_date"])
      )
    end

    @meeting.check_processing_complete!
  rescue StandardError => e
    Rails.logger.error("Meeting::ActionItem::Extract failed for meeting #{@meeting.id}: #{e.message}")
    @meeting.update_column(:status, "failed")
  end

  private

  def parse_json(content)
    json_str = content.gsub(/\A```(?:json)?\n?/, "").gsub(/\n?```\z/, "").strip
    JSON.parse(json_str)
  rescue JSON::ParserError => e
    Rails.logger.error("Failed to parse action items JSON: #{e.message}")
    []
  end

  def parse_date(date_str)
    return nil if date_str.nil? || date_str.to_s.empty?
    Date.parse(date_str)
  rescue Date::Error
    nil
  end
end
