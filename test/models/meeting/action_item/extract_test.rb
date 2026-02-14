require "test_helper"

class Meeting::ActionItem::ExtractTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:content)

  setup do
    @meeting = meetings(:two)
    @meeting.update_column(:status, "processing")
    @transcript = transcripts(:two)
    @transcript.update_column(:status, "completed")

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
    mock_chat.expect(:ask, FakeResponse.new(fake_response), [ String ])

    RubyLLM.stub(:chat, ->(**_kwargs) { mock_chat }) do
      Meeting::ActionItem::Extract.perform_now(@meeting.id)
    end

    items = @meeting.reload.action_items
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
    fake_response = [ { "description" => "Do something", "assignee" => nil, "due_date" => nil } ].to_json
    mock_chat = Minitest::Mock.new
    mock_chat.expect(:ask, FakeResponse.new(fake_response), [ String ])

    @meeting.create_summary!(model_used: "test")
    @meeting.summary.update!(content: "Test summary")

    RubyLLM.stub(:chat, ->(**_kwargs) { mock_chat }) do
      Meeting::ActionItem::Extract.perform_now(@meeting.id)
    end

    assert_equal "completed", @meeting.reload.status
    mock_chat.verify
  end

  test "handles empty action items array" do
    mock_chat = Minitest::Mock.new
    mock_chat.expect(:ask, FakeResponse.new("[]"), [ String ])

    RubyLLM.stub(:chat, ->(**_kwargs) { mock_chat }) do
      Meeting::ActionItem::Extract.perform_now(@meeting.id)
    end

    assert_equal 0, @meeting.action_items.count
    mock_chat.verify
  end

  test "handles JSON wrapped in markdown code block" do
    fake_response = "```json\n[{\"description\": \"Test item\", \"assignee\": null, \"due_date\": null}]\n```"
    mock_chat = Minitest::Mock.new
    mock_chat.expect(:ask, FakeResponse.new(fake_response), [ String ])

    RubyLLM.stub(:chat, ->(**_kwargs) { mock_chat }) do
      Meeting::ActionItem::Extract.perform_now(@meeting.id)
    end

    assert_equal 1, @meeting.action_items.count
    assert_equal "Test item", @meeting.action_items.first.description
    mock_chat.verify
  end

  test "skips if action items already exist" do
    @meeting.action_items.create!(description: "Existing item")

    Meeting::ActionItem::Extract.perform_now(@meeting.id)

    assert_equal 1, @meeting.action_items.count
    assert_equal "Existing item", @meeting.action_items.first.description
  end

  test "handles AI error gracefully — marks meeting as failed" do
    RubyLLM.stub(:chat, ->(**_kwargs) { raise StandardError, "API timeout" }) do
      Meeting::ActionItem::Extract.perform_now(@meeting.id)
    end

    assert_equal "failed", @meeting.reload.status
  end

  test "deduplicates semantically similar action items" do
    fake_response = [
      { "description" => "Draft the agenda including screenshots, requirements, device testing checklist, and book recurring invite for Wednesdays at 10am", "assignee" => "Mark", "due_date" => "2026-02-14" },
      { "description" => "Draft the agenda for mandatory design-to-dev handoff review meeting, include screenshots, requirements, device testing checklist, and book recurring invite for Wednesdays at 10am", "assignee" => "Mark", "due_date" => "2026-02-14" },
      { "description" => "Compile a quick one pager of the top recurring front end issues from this Sprint", "assignee" => "Leia", "due_date" => "2026-02-18" },
      { "description" => "Compile a quick one-pager of the top recurring front-end issues from Sprint 14. Pull bug tickets and add notes for review in grooming next week.", "assignee" => "Leia", "due_date" => "2026-02-18" },
      { "description" => "Set up template agenda for handoff review meeting", "assignee" => "Mark", "due_date" => nil }
    ].to_json

    mock_chat = Minitest::Mock.new
    mock_chat.expect(:ask, FakeResponse.new(fake_response), [ String ])

    RubyLLM.stub(:chat, ->(**_kwargs) { mock_chat }) do
      Meeting::ActionItem::Extract.perform_now(@meeting.id)
    end

    items = @meeting.reload.action_items
    # Should keep 3 unique items, not 5
    assert_equal 3, items.count

    mark_items = items.where(assignee: "Mark")
    leia_items = items.where(assignee: "Leia")
    assert_equal 2, mark_items.count
    assert_equal 1, leia_items.count

    mock_chat.verify
  end

  test "dedup prompt instructs AI to avoid duplicates" do
    assert_includes Meeting::ActionItem::Extract::SYSTEM_PROMPT.downcase, "duplicate"
  end
end
