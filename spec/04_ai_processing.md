# Spec 4: AI Processing (Summary + Action Items)

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build two parallel AI processing jobs that generate meeting summaries and extract action items from transcripts using RubyLLM with Claude Sonnet.

**Architecture:** Both jobs run in parallel after `FetchExportJob` completes. They share a `TranscriptFormatter` service that converts `TranscriptSegment` records into readable text. Each job creates its respective model records and calls `Meeting#check_processing_complete!` to transition the meeting to `completed` when both are done.

**Tech Stack:** RubyLLM gem (already configured with Claude + OpenAI keys), Solid Queue.

**Dependencies:** Spec 1 (models), Spec 3 (pipeline triggers these jobs).

---

## AI Model Configuration

- **Default model:** `claude-sonnet-4-20250514` (via RubyLLM / Anthropic)
- **Configurable via:** `Rails.application.config.ai_model` (set in initializer)
- **Fallback:** Graceful error handling with retries

---

### Task 1: AI Configuration Initializer

**Files:**
- Create: `config/initializers/ai.rb`

**Step 1: Create the initializer**

```ruby
# config/initializers/ai.rb
Rails.application.config.ai = ActiveSupport::OrderedOptions.new
Rails.application.config.ai.default_model = ENV.fetch("AI_MODEL", "claude-sonnet-4-20250514")
```

**Step 2: Commit**

```bash
git add -A && git commit -m "feat: add AI model configuration initializer"
```

---

### Task 2: TranscriptFormatter Service

**Files:**
- Create: `app/services/transcript_formatter.rb`
- Test: `test/services/transcript_formatter_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/services/transcript_formatter_test.rb
require "test_helper"

class TranscriptFormatterTest < ActiveSupport::TestCase
  test "formats transcript segments with speaker labels and timestamps" do
    transcript = transcripts(:one)
    # Uses fixtures: one_first, one_second, one_third segments

    result = TranscriptFormatter.new(transcript).format

    assert_includes result, "Speaker 1 [00:00:00]:"
    assert_includes result, "Hello everyone, welcome to the weekly standup."
    assert_includes result, "Speaker 2 [00:00:03]:"
    assert_includes result, "Thanks. My update is that the API integration is done."
    assert_includes result, "Speaker 1 [00:00:08]:"
    assert_includes result, "Great work. Let's move on to the next topic."
  end

  test "returns empty string for transcript with no segments" do
    transcript = transcripts(:two)
    result = TranscriptFormatter.new(transcript).format
    assert_equal "", result
  end

  test "handles nil start_time gracefully" do
    transcript = transcripts(:two)
    transcript.transcript_segments.create!(
      speaker: "Speaker 1",
      content: "No timestamp here.",
      start_time: nil,
      end_time: nil,
      position: 0
    )

    result = TranscriptFormatter.new(transcript).format
    assert_includes result, "Speaker 1 [00:00:00]: No timestamp here."
  end

  test "formats long timestamps correctly" do
    transcript = transcripts(:two)
    transcript.transcript_segments.create!(
      speaker: "Speaker 1",
      content: "An hour in.",
      start_time: 3661.5, # 1:01:01
      end_time: 3665.0,
      position: 0
    )

    result = TranscriptFormatter.new(transcript).format
    assert_includes result, "Speaker 1 [01:01:01]: An hour in."
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/transcript_formatter_test.rb`
Expected: FAIL

**Step 3: Implement the formatter**

```ruby
# app/services/transcript_formatter.rb
class TranscriptFormatter
  def initialize(transcript)
    @transcript = transcript
  end

  def format
    @transcript.transcript_segments.order(:position).map do |segment|
      timestamp = format_timestamp(segment.start_time)
      "#{segment.speaker} [#{timestamp}]: #{segment.content}"
    end.join("\n\n")
  end

  private

  def format_timestamp(seconds)
    return "00:00:00" if seconds.nil?
    Time.at(seconds.to_f).utc.strftime("%H:%M:%S")
  end
end
```

**Step 4: Run tests**

Run: `bin/rails test test/services/transcript_formatter_test.rb`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add -A && git commit -m "feat: add TranscriptFormatter service for AI prompt input"
```

---

### Task 3: GenerateSummaryJob

**Files:**
- Create: `app/jobs/generate_summary_job.rb`
- Test: `test/jobs/generate_summary_job_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/jobs/generate_summary_job_test.rb
require "test_helper"

class GenerateSummaryJobTest < ActiveJob::TestCase
  setup do
    @meeting = meetings(:two)
    @meeting.update!(status: :processing)
    @transcript = transcripts(:two)
    @transcript.update!(status: :completed)

    # Add some segments to transcript :two
    @transcript.transcript_segments.create!(
      speaker: "Speaker 1", content: "Let's discuss the Q3 roadmap.", start_time: 0.0, end_time: 3.0, position: 0
    )
    @transcript.transcript_segments.create!(
      speaker: "Speaker 2", content: "I think we should focus on the API.", start_time: 3.0, end_time: 6.0, position: 1
    )
  end

  test "creates a summary from transcript" do
    fake_response = "## Meeting Overview\nThe team discussed the Q3 roadmap.\n\n## Key Discussion Points\n- API focus for Q3"

    # Mock RubyLLM chat
    mock_chat = Minitest::Mock.new
    mock_chat.expect(:ask, OpenStruct.new(content: fake_response), [String])

    RubyLLM.stub(:chat, ->(**_kwargs) { mock_chat }) do
      GenerateSummaryJob.perform_now(@meeting.id)
    end

    @meeting.reload
    summary = @meeting.summary
    assert_not_nil summary
    assert_includes summary.content, "Q3 roadmap"
    assert_equal Rails.application.config.ai.default_model, summary.model_used

    mock_chat.verify
  end

  test "calls check_processing_complete! after creating summary" do
    fake_response = "Summary content"
    mock_chat = Minitest::Mock.new
    mock_chat.expect(:ask, OpenStruct.new(content: fake_response), [String])

    # Also create action items so check_processing_complete! can transition
    @meeting.action_items.create!(description: "Test action")

    RubyLLM.stub(:chat, ->(**_kwargs) { mock_chat }) do
      GenerateSummaryJob.perform_now(@meeting.id)
    end

    # Should be completed because both summary and action items exist
    assert_equal "completed", @meeting.reload.status

    mock_chat.verify
  end

  test "handles AI error gracefully" do
    RubyLLM.stub(:chat, ->(**_kwargs) { raise StandardError, "API timeout" }) do
      GenerateSummaryJob.perform_now(@meeting.id)
    end

    # Meeting should be marked as failed
    assert_equal "failed", @meeting.reload.status
  end

  test "skips if summary already exists" do
    @meeting.create_summary!(content: "Existing summary", model_used: "test")

    # Should not call RubyLLM at all
    GenerateSummaryJob.perform_now(@meeting.id)

    assert_equal "Existing summary", @meeting.summary.content
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/jobs/generate_summary_job_test.rb`
Expected: FAIL

**Step 3: Implement the job**

```ruby
# app/jobs/generate_summary_job.rb
class GenerateSummaryJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :polynomially_longer, attempts: 3

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

  def perform(meeting_id)
    meeting = Meeting.find(meeting_id)
    return if meeting.summary.present?

    transcript = meeting.transcript
    formatted_text = TranscriptFormatter.new(transcript).format

    model = Rails.application.config.ai.default_model
    chat = RubyLLM.chat(model: model)
    response = chat.ask("#{SYSTEM_PROMPT}\n\n---\n\nTranscript:\n\n#{formatted_text}")

    meeting.create_summary!(
      content: response.content,
      model_used: model
    )

    meeting.check_processing_complete!
    broadcast_status(meeting)
  rescue StandardError => e
    meeting = Meeting.find(meeting_id)
    if executions < max_attempts
      raise # Let retry_on handle it
    else
      meeting.update!(status: :failed)
      broadcast_status(meeting)
      Rails.logger.error("GenerateSummaryJob failed for meeting #{meeting_id}: #{e.message}")
    end
  end

  private

  def max_attempts
    3
  end

  def broadcast_status(meeting)
    Turbo::StreamsChannel.broadcast_replace_to(
      meeting,
      target: "meeting_#{meeting.id}_status",
      partial: "meetings/status",
      locals: { meeting: meeting }
    )

    # Also broadcast the summary partial if it was created
    if meeting.summary.present?
      Turbo::StreamsChannel.broadcast_replace_to(
        meeting,
        target: "meeting_#{meeting.id}_summary",
        partial: "meetings/summary",
        locals: { summary: meeting.summary }
      )
    end
  end
end
```

**Step 4: Run tests**

Run: `bin/rails test test/jobs/generate_summary_job_test.rb`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add -A && git commit -m "feat: add GenerateSummaryJob with Claude Sonnet integration"
```

---

### Task 4: ExtractActionItemsJob

**Files:**
- Create: `app/jobs/extract_action_items_job.rb`
- Test: `test/jobs/extract_action_items_job_test.rb`

**Step 1: Write the failing tests**

```ruby
# test/jobs/extract_action_items_job_test.rb
require "test_helper"

class ExtractActionItemsJobTest < ActiveJob::TestCase
  setup do
    @meeting = meetings(:two)
    @meeting.update!(status: :processing)
    @transcript = transcripts(:two)
    @transcript.update!(status: :completed)

    @transcript.transcript_segments.create!(
      speaker: "Speaker 1", content: "Sarah, can you send the Q3 report by Friday?",
      start_time: 0.0, end_time: 4.0, position: 0
    )
    @transcript.transcript_segments.create!(
      speaker: "Speaker 2", content: "Sure, I'll also schedule a review meeting.",
      start_time: 4.0, end_time: 7.0, position: 1
    )
  end

  test "extracts action items from transcript" do
    fake_response = [
      { "description" => "Send the Q3 report", "assignee" => "Sarah", "due_date" => "2026-02-13" },
      { "description" => "Schedule a review meeting", "assignee" => "Speaker 2", "due_date" => nil }
    ].to_json

    mock_chat = Minitest::Mock.new
    mock_chat.expect(:ask, OpenStruct.new(content: fake_response), [String])

    RubyLLM.stub(:chat, ->(**_kwargs) { mock_chat }) do
      ExtractActionItemsJob.perform_now(@meeting.id)
    end

    @meeting.reload
    items = @meeting.action_items
    assert_equal 2, items.count

    first = items.find_by(assignee: "Sarah")
    assert_equal "Send the Q3 report", first.description
    assert_equal Date.parse("2026-02-13"), first.due_date
    assert_equal false, first.completed

    second = items.find_by(assignee: "Speaker 2")
    assert_equal "Schedule a review meeting", second.description
    assert_nil second.due_date

    mock_chat.verify
  end

  test "calls check_processing_complete! after creating action items" do
    fake_response = [{ "description" => "Do something", "assignee" => nil, "due_date" => nil }].to_json

    mock_chat = Minitest::Mock.new
    mock_chat.expect(:ask, OpenStruct.new(content: fake_response), [String])

    # Create summary so completion check can transition
    @meeting.create_summary!(content: "Test summary", model_used: "test")

    RubyLLM.stub(:chat, ->(**_kwargs) { mock_chat }) do
      ExtractActionItemsJob.perform_now(@meeting.id)
    end

    assert_equal "completed", @meeting.reload.status
    mock_chat.verify
  end

  test "handles empty action items array" do
    fake_response = "[]"

    mock_chat = Minitest::Mock.new
    mock_chat.expect(:ask, OpenStruct.new(content: fake_response), [String])

    RubyLLM.stub(:chat, ->(**_kwargs) { mock_chat }) do
      ExtractActionItemsJob.perform_now(@meeting.id)
    end

    assert_equal 0, @meeting.action_items.count
    mock_chat.verify
  end

  test "handles AI returning JSON wrapped in markdown code block" do
    fake_response = "```json\n[{\"description\": \"Test item\", \"assignee\": null, \"due_date\": null}]\n```"

    mock_chat = Minitest::Mock.new
    mock_chat.expect(:ask, OpenStruct.new(content: fake_response), [String])

    RubyLLM.stub(:chat, ->(**_kwargs) { mock_chat }) do
      ExtractActionItemsJob.perform_now(@meeting.id)
    end

    assert_equal 1, @meeting.action_items.count
    assert_equal "Test item", @meeting.action_items.first.description
    mock_chat.verify
  end

  test "skips if action items already exist" do
    @meeting.action_items.create!(description: "Existing item")

    # Should not call RubyLLM
    ExtractActionItemsJob.perform_now(@meeting.id)

    assert_equal 1, @meeting.action_items.count
    assert_equal "Existing item", @meeting.action_items.first.description
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/jobs/extract_action_items_job_test.rb`
Expected: FAIL

**Step 3: Implement the job**

```ruby
# app/jobs/extract_action_items_job.rb
class ExtractActionItemsJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :polynomially_longer, attempts: 3

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

    Example output:
    [
      {"description": "Send the Q3 report to the finance team", "assignee": "Sarah", "due_date": "2026-02-15"},
      {"description": "Schedule follow-up meeting", "assignee": "Tom", "due_date": null}
    ]
  PROMPT

  def perform(meeting_id)
    meeting = Meeting.find(meeting_id)
    return if meeting.action_items.any?

    transcript = meeting.transcript
    formatted_text = TranscriptFormatter.new(transcript).format

    model = Rails.application.config.ai.default_model
    chat = RubyLLM.chat(model: model)
    response = chat.ask("#{SYSTEM_PROMPT}\n\n---\n\nTranscript:\n\n#{formatted_text}")

    items = parse_action_items(response.content)

    items.each do |item|
      meeting.action_items.create!(
        description: item["description"],
        assignee: item["assignee"],
        due_date: parse_date(item["due_date"])
      )
    end

    meeting.check_processing_complete!
    broadcast_status(meeting)
  rescue StandardError => e
    meeting = Meeting.find(meeting_id)
    if executions < max_attempts
      raise
    else
      meeting.update!(status: :failed)
      broadcast_status(meeting)
      Rails.logger.error("ExtractActionItemsJob failed for meeting #{meeting_id}: #{e.message}")
    end
  end

  private

  def max_attempts
    3
  end

  def parse_action_items(content)
    # Strip markdown code block if present
    json_str = content.gsub(/\A```(?:json)?\n?/, "").gsub(/\n?```\z/, "").strip
    JSON.parse(json_str)
  rescue JSON::ParserError => e
    Rails.logger.error("Failed to parse action items JSON: #{e.message}\nContent: #{content}")
    []
  end

  def parse_date(date_str)
    return nil if date_str.nil? || date_str.empty?
    Date.parse(date_str)
  rescue Date::Error
    nil
  end

  def broadcast_status(meeting)
    Turbo::StreamsChannel.broadcast_replace_to(
      meeting,
      target: "meeting_#{meeting.id}_status",
      partial: "meetings/status",
      locals: { meeting: meeting }
    )

    if meeting.action_items.any?
      Turbo::StreamsChannel.broadcast_replace_to(
        meeting,
        target: "meeting_#{meeting.id}_action_items",
        partial: "meetings/action_items",
        locals: { action_items: meeting.action_items }
      )
    end
  end
end
```

**Step 4: Run tests**

Run: `bin/rails test test/jobs/extract_action_items_job_test.rb`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add -A && git commit -m "feat: add ExtractActionItemsJob with structured JSON extraction"
```

---

### Task 5: Meeting#check_processing_complete! — Full Integration Test

**Files:**
- Modify: `test/models/meeting_test.rb`

**Step 1: Add integration test verifying the full completion flow**

```ruby
# Add to test/models/meeting_test.rb

test "completion check works when summary is created first then action items" do
  meeting = Meeting.create!(
    title: "Integration Test", language: "en-US",
    user: users(:one), status: :processing
  )

  # Summary arrives first
  meeting.create_summary!(content: "Test", model_used: "test")
  meeting.check_processing_complete!
  assert_equal "processing", meeting.reload.status # Not yet complete

  # Action items arrive second
  meeting.action_items.create!(description: "Do something")
  meeting.check_processing_complete!
  assert_equal "completed", meeting.reload.status # Now complete
end

test "completion check works when action items arrive first then summary" do
  meeting = Meeting.create!(
    title: "Integration Test 2", language: "en-US",
    user: users(:one), status: :processing
  )

  # Action items arrive first
  meeting.action_items.create!(description: "Do something")
  meeting.check_processing_complete!
  assert_equal "processing", meeting.reload.status

  # Summary arrives second
  meeting.create_summary!(content: "Test", model_used: "test")
  meeting.check_processing_complete!
  assert_equal "completed", meeting.reload.status
end
```

**Step 2: Run tests**

Run: `bin/rails test test/models/meeting_test.rb`
Expected: All tests PASS

**Step 3: Commit**

```bash
git add -A && git commit -m "test: add completion flow integration tests"
```
