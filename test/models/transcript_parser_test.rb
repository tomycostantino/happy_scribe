require "test_helper"

class TranscriptParserTest < ActiveSupport::TestCase
  setup do
    @transcript = transcripts(:two)
  end

  test "parses HappyScribe export into speaker segments" do
    data = [
      {
        "speaker" => "Speaker 1",
        "data_start" => 0.0,
        "data_end" => 2.0,
        "words" => [
          { "text" => "Hello", "data_start" => 0.0, "data_end" => 1.0 },
          { "text" => "everyone.", "data_start" => 1.0, "data_end" => 2.0 }
        ]
      },
      {
        "speaker" => "Speaker 2",
        "data_start" => 3.0,
        "data_end" => 4.0,
        "words" => [
          { "text" => "Hi", "data_start" => 3.0, "data_end" => 3.5 },
          { "text" => "there.", "data_start" => 3.5, "data_end" => 4.0 }
        ]
      }
    ]

    @transcript.parse_happyscribe_export(data)

    segments = @transcript.transcript_segments.order(:position)
    assert_equal 2, segments.count

    assert_equal "Speaker 1", segments[0].speaker
    assert_equal "Hello everyone.", segments[0].content
    assert_in_delta 0.0, segments[0].start_time
    assert_in_delta 2.0, segments[0].end_time
    assert_equal 0, segments[0].position

    assert_equal "Speaker 2", segments[1].speaker
    assert_equal "Hi there.", segments[1].content
    assert_in_delta 3.0, segments[1].start_time
    assert_in_delta 4.0, segments[1].end_time
    assert_equal 1, segments[1].position
  end

  test "handles empty array" do
    @transcript.parse_happyscribe_export([])
    assert_equal 0, @transcript.transcript_segments.count
  end

  test "clears existing segments before parsing" do
    @transcript.transcript_segments.create!(speaker: "Old", content: "Old", position: 0)

    data = [
      { "speaker" => "New", "data_start" => 0.0, "data_end" => 1.0,
        "words" => [ { "text" => "New content.", "data_start" => 0.0, "data_end" => 1.0 } ] }
    ]

    @transcript.parse_happyscribe_export(data)
    assert_equal 1, @transcript.transcript_segments.count
    assert_equal "New content.", @transcript.transcript_segments.first.content
  end
end
