require "test_helper"

class TranscriptTest < ActiveSupport::TestCase
  test "valid transcript" do
    transcript = Transcript.new(
      meeting: meetings(:one),
      status: :pending
    )
    assert transcript.valid?
  end

  test "requires a meeting" do
    transcript = Transcript.new(status: :pending)
    assert_not transcript.valid?
  end

  test "defaults status to pending" do
    transcript = Transcript.new
    assert_equal "pending", transcript.status
  end

  test "status enum values" do
    assert_equal(
      { "pending" => "pending", "processing" => "processing",
        "completed" => "completed", "failed" => "failed" },
      Transcript.statuses
    )
  end

  test "belongs to meeting" do
    transcript = transcripts(:one)
    assert_instance_of Meeting, transcript.meeting
  end

  test "stores happyscribe_id" do
    transcript = transcripts(:one)
    transcript.update!(happyscribe_id: "abc123")
    assert_equal "abc123", transcript.reload.happyscribe_id
  end

  test "stores rich text content via Action Text" do
    transcript = transcripts(:one)
    transcript.update!(content: "<p>Speaker 1: Hello everyone.</p>")
    assert transcript.content.present?
  end
end
