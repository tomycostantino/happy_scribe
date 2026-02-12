require "test_helper"

class TranscriptSegmentTest < ActiveSupport::TestCase
  test "valid segment with required attributes" do
    segment = TranscriptSegment.new(
      transcript: transcripts(:one),
      speaker: "Speaker 1",
      content: "Hello everyone, welcome to the meeting.",
      start_time: 0.0,
      end_time: 5.5,
      position: 0
    )
    assert segment.valid?
  end

  test "requires a transcript" do
    segment = TranscriptSegment.new(
      speaker: "Speaker 1",
      content: "Hello",
      position: 0
    )
    assert_not segment.valid?
  end

  test "requires content" do
    segment = TranscriptSegment.new(
      transcript: transcripts(:one),
      speaker: "Speaker 1",
      position: 0
    )
    assert_not segment.valid?
    assert_includes segment.errors[:content], "can't be blank"
  end

  test "requires position" do
    segment = TranscriptSegment.new(
      transcript: transcripts(:one),
      speaker: "Speaker 1",
      content: "Hello"
    )
    assert_not segment.valid?
    assert_includes segment.errors[:position], "can't be blank"
  end

  test "orders by position by default" do
    # Segments should come back ordered by position
    segments = transcripts(:one).transcript_segments.order(:position)
    positions = segments.map(&:position)
    assert_equal positions.sort, positions
  end
end
