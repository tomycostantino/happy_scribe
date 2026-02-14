require "test_helper"

class TranscriptFormattableTest < ActiveSupport::TestCase
  test "formatted_text returns speaker-labeled transcript" do
    transcript = transcripts(:one)
    text = transcript.formatted_text

    assert_includes text, "Speaker 1 [00:00:00]: Hello everyone, welcome to the weekly standup."
    assert_includes text, "Speaker 2 [00:00:03]: Thanks. My update is that the API integration is done."
    assert_includes text, "Speaker 1 [00:00:08]: Great work. Let's move on to the next topic."
  end

  test "formatted_text separates segments with double newlines" do
    transcript = transcripts(:one)
    text = transcript.formatted_text

    segments = text.split("\n\n")
    assert_equal 3, segments.count
  end

  test "formatted_text handles nil start_time" do
    transcript = transcripts(:two)
    transcript.transcript_segments.create!(
      speaker: "Speaker 1",
      content: "Test content",
      start_time: nil,
      end_time: 1.0,
      position: 0
    )

    text = transcript.formatted_text
    assert_includes text, "[00:00:00]:"
  end

  test "formatted_text handles durations over 24 hours" do
    transcript = transcripts(:two)
    transcript.transcript_segments.create!(
      speaker: "Speaker 1",
      content: "Long meeting",
      start_time: 90061.0, # 25 hours, 1 minute, 1 second
      end_time: 90062.0,
      position: 0
    )

    text = transcript.formatted_text
    assert_includes text, "[25:01:01]:"
  end

  test "formatted_text orders by position" do
    transcript = transcripts(:two)
    # Create segments out of order
    transcript.transcript_segments.create!(speaker: "B", content: "Second", start_time: 5.0, end_time: 10.0, position: 1)
    transcript.transcript_segments.create!(speaker: "A", content: "First", start_time: 0.0, end_time: 5.0, position: 0)

    text = transcript.formatted_text
    assert text.index("First") < text.index("Second")
  end
end
