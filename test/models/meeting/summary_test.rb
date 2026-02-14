require "test_helper"

class Meeting::SummaryTest < ActiveSupport::TestCase
  test "valid summary" do
    summary = Meeting::Summary.new(meeting: meetings(:one), model_used: "claude-sonnet-4-20250514")
    summary.content = "This meeting covered project updates."
    assert summary.valid?
  end

  test "requires a meeting" do
    summary = Meeting::Summary.new(model_used: "claude-sonnet-4-20250514")
    summary.content = "Some text"
    assert_not summary.valid?
  end

  test "belongs to meeting" do
    summary = meeting_summaries(:one)
    assert_instance_of Meeting, summary.meeting
  end

  test "stores rich text content via Action Text" do
    summary = Meeting::Summary.create!(meeting: meetings(:two), model_used: "test")
    summary.update!(content: "<h2>Summary</h2><p>The team discussed progress.</p>")
    assert summary.content.present?
  end
end
