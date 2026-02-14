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
    - Do NOT extract duplicate action items. If the same task is mentioned multiple times
      (even with slightly different wording), include it only once with the most complete description.
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

    deduplicated = deduplicate(items)

    deduplicated.each do |item|
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

  # Remove near-duplicate items. Two items are considered duplicates if they
  # share the same assignee and their descriptions have high word overlap.
  # Uses >70% threshold for assigned items, >90% for unassigned items
  # (to avoid merging genuinely different tasks that happen to share words).
  # When duplicates are found, keep the longer (more detailed) description.
  def deduplicate(items)
    kept = []

    items.each do |item|
      duplicate = kept.find { |existing| similar?(existing, item) }
      if duplicate
        # Keep the longer description
        if item["description"].to_s.length > duplicate["description"].to_s.length
          kept.delete(duplicate)
          kept << item
        end
      else
        kept << item
      end
    end

    kept
  end

  SIMILARITY_THRESHOLD = 0.7
  UNASSIGNED_SIMILARITY_THRESHOLD = 0.9

  def similar?(a, b)
    assignee_a = normalize_assignee(a["assignee"])
    assignee_b = normalize_assignee(b["assignee"])
    return false unless assignee_a == assignee_b

    words_a = normalize_words(a["description"])
    words_b = normalize_words(b["description"])
    return false if words_a.empty? || words_b.empty?

    overlap = (words_a & words_b).size
    smaller = [ words_a.size, words_b.size ].min
    threshold = assignee_a.empty? ? UNASSIGNED_SIMILARITY_THRESHOLD : SIMILARITY_THRESHOLD
    overlap.to_f / smaller > threshold
  end

  def normalize_words(text)
    text.to_s.downcase.gsub(/[^a-z0-9\s]/, " ").split
  end

  def normalize_assignee(assignee)
    assignee.to_s.strip.downcase
  end

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
